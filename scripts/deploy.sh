#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER_DIR="${HUSTLEOPS_DEPLOY_SCRIPT_DIR:-$SCRIPT_DIR}"

ENV_FILE="$PROJECT_ROOT/.env"
ENV_TEMPLATE_FILE="$PROJECT_ROOT/.env.example"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.prod.yml"
MANIFEST_FILE="$PROJECT_ROOT/release-manifest.json"
VERIFICATION_FILE="$PROJECT_ROOT/release-verification.json"
BACKUP_DIR="$PROJECT_ROOT/backups"
TIMEOUT_SECONDS=600

COMMAND=""
WITH_ANCILLARY=0
SKIP_PULL=0
SKIP_SIGNATURE_VERIFY=0
SKIP_BACKUP=0
SKIP_BOOTSTRAP=0
NO_START=0
DRY_RUN=0
YES=0
VERBOSE=0
QUIET=0

usage() {
  cat <<'EOF'
Usage: ./scripts/deploy.sh {setup|update|start|stop|status|preflight|backup|migrate|bootstrap} [options]

Commands:
  setup       Run first-install flow: preflight, backup, migration, bootstrap, start
  update      Run update flow: preflight, backup, migration, bootstrap, start
  start       Start core services
  stop        Stop services
  status      Show Docker Compose service status
  preflight   Run preflight checks only
  backup      Capture PostgreSQL backup only
  migrate     Run database migration only
  bootstrap   Run initial-admin bootstrap only

Options:
  --env-file PATH
  --env-template-file PATH
  --compose-file PATH
  --manifest-file PATH
  --verification-file PATH
  --backup-dir PATH
  --timeout-seconds SECONDS
  --with-ancillary
  --skip-pull
  --skip-signature-verify
  --skip-backup
  --skip-bootstrap
  --no-start
  --dry-run
  --yes
  --verbose
  --quiet
  -h, --help

The setup and update flows call scripts/preflight.sh, scripts/backup-postgres.sh,
scripts/run-migration.sh, and the backend-bootstrap Compose service.
Release-managed image and metadata values are synced from .env.example into
.env before preflight; operator-provided secrets are preserved.
EOF
}

fail() {
  local status="${2:-1}"
  printf 'ERROR: %s\n' "$1" >&2
  exit "$status"
}

note() {
  [[ "$QUIET" -eq 1 ]] && return
  printf '%s\n' "$*"
}

step() {
  local current="$1"
  local total="$2"
  local message="$3"

  note "[$current/$total] $message"
}

resolve_path() {
  local value="$1"

  if [[ "$value" = /* ]]; then
    printf '%s\n' "$value"
    return
  fi

  printf '%s\n' "$PWD/${value#./}"
}

run_cmd() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY RUN:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi

  if [[ "$VERBOSE" -eq 1 ]]; then
    printf 'Running:'
    printf ' %q' "$@"
    printf '\n'
  fi

  "$@"
}

require_file() {
  local file_path="$1"
  local label="$2"

  [[ -f "$file_path" ]] || fail "$label not found: $file_path"
}

require_command() {
  local command_name="$1"

  command -v "$command_name" >/dev/null 2>&1 || fail "$command_name must be installed and on PATH."
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

COMMAND="$1"
shift

case "$COMMAND" in
  setup|update|start|stop|status|preflight|backup|migrate|bootstrap)
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    fail "Unknown command: $COMMAND"
    ;;
esac

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      [[ $# -ge 2 ]] || fail "Missing value for --env-file."
      ENV_FILE="$2"
      shift 2
      ;;
    --env-template-file)
      [[ $# -ge 2 ]] || fail "Missing value for --env-template-file."
      ENV_TEMPLATE_FILE="$2"
      shift 2
      ;;
    --compose-file)
      [[ $# -ge 2 ]] || fail "Missing value for --compose-file."
      COMPOSE_FILE="$2"
      shift 2
      ;;
    --manifest-file)
      [[ $# -ge 2 ]] || fail "Missing value for --manifest-file."
      MANIFEST_FILE="$2"
      shift 2
      ;;
    --verification-file)
      [[ $# -ge 2 ]] || fail "Missing value for --verification-file."
      VERIFICATION_FILE="$2"
      shift 2
      ;;
    --backup-dir)
      [[ $# -ge 2 ]] || fail "Missing value for --backup-dir."
      BACKUP_DIR="$2"
      shift 2
      ;;
    --timeout-seconds)
      [[ $# -ge 2 ]] || fail "Missing value for --timeout-seconds."
      TIMEOUT_SECONDS="$2"
      shift 2
      ;;
    --with-ancillary)
      WITH_ANCILLARY=1
      shift
      ;;
    --skip-pull)
      SKIP_PULL=1
      shift
      ;;
    --skip-signature-verify)
      SKIP_SIGNATURE_VERIFY=1
      shift
      ;;
    --skip-backup)
      SKIP_BACKUP=1
      shift
      ;;
    --skip-bootstrap)
      SKIP_BOOTSTRAP=1
      shift
      ;;
    --no-start)
      NO_START=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --yes)
      YES=1
      shift
      ;;
    --verbose)
      VERBOSE=1
      shift
      ;;
    --quiet)
      QUIET=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ "$TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || fail "--timeout-seconds must be a positive integer."
[[ "$TIMEOUT_SECONDS" -gt 0 ]] || fail "--timeout-seconds must be greater than zero."

ENV_FILE="$(resolve_path "$ENV_FILE")"
ENV_TEMPLATE_FILE="$(resolve_path "$ENV_TEMPLATE_FILE")"
COMPOSE_FILE="$(resolve_path "$COMPOSE_FILE")"
MANIFEST_FILE="$(resolve_path "$MANIFEST_FILE")"
VERIFICATION_FILE="$(resolve_path "$VERIFICATION_FILE")"
BACKUP_DIR="$(resolve_path "$BACKUP_DIR")"

confirm_production_action() {
  [[ "$YES" -eq 1 ]] && return
  [[ "$DRY_RUN" -eq 1 ]] && return

  printf 'This will run the HustleOps %s flow against %s. Continue? [y/N] ' "$COMMAND" "$ENV_FILE"
  read -r answer
  case "$answer" in
    y|Y|yes|YES)
      ;;
    *)
      fail "Aborted."
      ;;
  esac
}

check_tools() {
  require_command docker

  if [[ "$DRY_RUN" -eq 0 ]]; then
    docker compose version >/dev/null 2>&1 || fail "Docker Compose v2 must be available as 'docker compose'."
  fi

  case "$COMMAND" in
    setup|update)
      require_command node
      require_command timeout
      if [[ "$SKIP_SIGNATURE_VERIFY" -eq 0 ]]; then
        require_command cosign
      fi
      ;;
    preflight)
      if [[ "$SKIP_SIGNATURE_VERIFY" -eq 0 ]]; then
        require_command node
        require_command cosign
      fi
      ;;
    migrate)
      require_command node
      require_command timeout
      ;;
  esac
}

check_files() {
  case "$COMMAND" in
    setup|update|preflight|backup|migrate|bootstrap|start|stop|status)
      require_file "$ENV_FILE" "Env file"
      require_file "$COMPOSE_FILE" "Compose file"
      ;;
  esac

  case "$COMMAND" in
    setup|update)
      require_file "$ENV_TEMPLATE_FILE" "Env template file"
      ;;
  esac

  case "$COMMAND" in
    setup|update|preflight|migrate)
      require_file "$MANIFEST_FILE" "Release manifest file"
      ;;
  esac

  case "$COMMAND" in
    setup|update|preflight)
      if [[ "$SKIP_SIGNATURE_VERIFY" -eq 0 ]]; then
        require_file "$VERIFICATION_FILE" "Release verification file"
      fi
      ;;
  esac
}

sync_release_env() {
  local managed_keys=(
    HUSTLEOPS_BACKEND_IMAGE
    HUSTLEOPS_FRONTEND_IMAGE
    HUSTLEOPS_BACKEND_MIGRATION_IMAGE
    HUSTLEOPS_RELEASE_TAG
    HUSTLEOPS_RELEASE_TRIGGER
  )

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY RUN: sync release-managed env keys from %q to %q\n' "$ENV_TEMPLATE_FILE" "$ENV_FILE"
    return 0
  fi

  if [[ "$VERBOSE" -eq 1 ]]; then
    printf 'Syncing release-managed env keys from %s to %s\n' "$ENV_TEMPLATE_FILE" "$ENV_FILE"
  fi

  node - "$ENV_FILE" "$ENV_TEMPLATE_FILE" "${managed_keys[@]}" <<'NODE'
const fs = require('node:fs');

const [envFile, envTemplateFile, ...managedKeys] = process.argv.slice(2);
const managedKeySet = new Set(managedKeys);
const assignmentPattern = /^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/;

function readAssignments(filePath) {
  const assignments = new Map();
  const content = fs.readFileSync(filePath, 'utf8');

  for (const line of content.split(/\n/)) {
    const match = line.match(assignmentPattern);
    if (!match) {
      continue;
    }
    assignments.set(match[1], match[2]);
  }

  return assignments;
}

const templateAssignments = readAssignments(envTemplateFile);
const missingTemplateKeys = managedKeys.filter(
  (key) => !templateAssignments.has(key),
);

if (missingTemplateKeys.length > 0) {
  console.error(
    `Env template is missing release-managed keys: ${missingTemplateKeys.join(', ')}`,
  );
  process.exit(1);
}

const envContent = fs.readFileSync(envFile, 'utf8');
const envLines = envContent.replace(/\n$/, '').split(/\n/);
const replacedKeys = new Set();
const nextLines = envLines.map((line) => {
  const match = line.match(assignmentPattern);
  if (!match || !managedKeySet.has(match[1])) {
    return line;
  }

  replacedKeys.add(match[1]);
  return `${match[1]}=${templateAssignments.get(match[1])}`;
});
const missingEnvKeys = managedKeys.filter((key) => !replacedKeys.has(key));

if (missingEnvKeys.length > 0) {
  if (nextLines.length > 0 && nextLines.at(-1) !== '') {
    nextLines.push('');
  }
  nextLines.push('# Release-managed values synced from .env.example');
  for (const key of missingEnvKeys) {
    nextLines.push(`${key}=${templateAssignments.get(key)}`);
  }
}

fs.writeFileSync(envFile, `${nextLines.join('\n')}\n`);
NODE
}

run_preflight() {
  local args=(
    "$HELPER_DIR/preflight.sh"
    --env-file "$ENV_FILE"
    --compose-file "$COMPOSE_FILE"
    --manifest-file "$MANIFEST_FILE"
    --verification-file "$VERIFICATION_FILE"
  )

  [[ "$SKIP_PULL" -eq 1 ]] && args+=(--skip-pull)
  [[ "$SKIP_SIGNATURE_VERIFY" -eq 1 ]] && args+=(--skip-signature-verify)

  run_cmd "${args[@]}"
}

prepare_postgres_for_backup() {
  if [[ "$SKIP_BACKUP" -eq 1 ]]; then
    return 0
  fi

  run_cmd docker compose \
    --env-file "$ENV_FILE" \
    -f "$COMPOSE_FILE" \
    up \
    -d \
    postgres
}

run_backup() {
  if [[ "$SKIP_BACKUP" -eq 1 ]]; then
    note "Skipping backup (--skip-backup)"
    return
  fi

  run_cmd "$HELPER_DIR/backup-postgres.sh" \
    --env-file "$ENV_FILE" \
    --compose-file "$COMPOSE_FILE" \
    --output-dir "$BACKUP_DIR"
}

run_migration() {
  local status

  run_cmd "$HELPER_DIR/run-migration.sh" \
    --env-file "$ENV_FILE" \
    --compose-file "$COMPOSE_FILE" \
    --manifest-file "$MANIFEST_FILE" \
    --timeout-seconds "$TIMEOUT_SECONDS" && return

  status=$?
  fail "Migration failed." "$status"
}

run_bootstrap() {
  if [[ "$SKIP_BOOTSTRAP" -eq 1 ]]; then
    note "Skipping bootstrap (--skip-bootstrap)"
    return
  fi

  run_cmd docker compose \
    --env-file "$ENV_FILE" \
    -f "$COMPOSE_FILE" \
    --profile bootstrap \
    run \
    --rm \
    backend-bootstrap
}

start_core_services() {
  run_cmd docker compose \
    --env-file "$ENV_FILE" \
    -f "$COMPOSE_FILE" \
    up \
    -d \
    backend \
    frontend \
    nginx
}

start_ancillary_services() {
  if [[ "$WITH_ANCILLARY" -ne 1 ]]; then
    return 0
  fi

  run_cmd docker compose \
    --env-file "$ENV_FILE" \
    -f "$COMPOSE_FILE" \
    --profile ancillary-public \
    up \
    -d \
    nginx-ancillary
}

show_status() {
  run_cmd docker compose \
    --env-file "$ENV_FILE" \
    -f "$COMPOSE_FILE" \
    ps
}

run_standard_flow() {
  confirm_production_action

  step 1 7 "Checking required tools and files"
  check_tools
  check_files
  step 2 7 "Syncing release-managed environment values"
  sync_release_env
  step 3 7 "Running preflight checks"
  run_preflight
  step 4 7 "Preparing PostgreSQL and capturing backup"
  prepare_postgres_for_backup
  run_backup
  step 5 7 "Applying database migrations"
  run_migration
  step 6 7 "Running bootstrap"
  run_bootstrap
  if [[ "$NO_START" -eq 0 ]]; then
    step 7 7 "Starting core services"
    start_core_services
    start_ancillary_services
    show_status
  else
    step 7 7 "Skipping service start (--no-start)"
  fi
}

case "$COMMAND" in
  setup)
    run_standard_flow
    ;;
  update)
    run_standard_flow
    ;;
  start)
    step 1 2 "Checking required tools and files"
    check_tools
    check_files
    step 2 2 "Starting core services"
    start_core_services
    start_ancillary_services
    show_status
    ;;
  stop)
    step 1 2 "Checking required tools and files"
    check_tools
    check_files
    step 2 2 "Stopping services"
    run_cmd docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" stop
    ;;
  status)
    step 1 2 "Checking required tools and files"
    check_tools
    check_files
    step 2 2 "Showing service status"
    show_status
    ;;
  preflight)
    step 1 2 "Checking required tools and files"
    check_tools
    check_files
    step 2 2 "Running preflight checks"
    run_preflight
    ;;
  backup)
    step 1 3 "Checking required tools and files"
    check_tools
    check_files
    step 2 3 "Preparing PostgreSQL"
    prepare_postgres_for_backup
    step 3 3 "Capturing PostgreSQL backup"
    run_backup
    ;;
  migrate)
    step 1 2 "Checking required tools and files"
    check_tools
    check_files
    step 2 2 "Applying database migrations"
    run_migration
    ;;
  bootstrap)
    step 1 2 "Checking required tools and files"
    check_tools
    check_files
    step 2 2 "Running bootstrap"
    run_bootstrap
    ;;
esac

note "Done."
