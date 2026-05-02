#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.prod.yml"
MANIFEST_FILE="$PROJECT_ROOT/release-manifest.json"
TIMEOUT_SECONDS=600

usage() {
  cat <<'EOF'
Usage: ./scripts/run-migration.sh [--env-file PATH] [--compose-file PATH] [--manifest-file PATH] [--timeout-seconds SECONDS]

Run the one-shot backend migration service and write a release-linked migration
success marker only after Prisma reports a successful or no-op migration.
EOF
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

note() {
  printf '==> %s\n' "$*"
}

print_sanitized_output() {
  sed -E 's#(postgres(ql)?://[^:/[:space:]]+):[^@[:space:]]+@#\1:***@#g' "$1"
}

resolve_path() {
  local value="$1"

  if [[ "$value" = /* ]]; then
    printf '%s\n' "$value"
    return
  fi

  printf '%s\n' "$PWD/${value#./}"
}

write_success_marker() {
  local output_file="$1"
  local exit_code="$2"

  node - \
    "$MANIFEST_FILE" \
    "$output_file" \
    "$TIMEOUT_SECONDS" \
    "$exit_code" <<'NODE'
const fs = require('node:fs');
const path = require('node:path');

const [manifestFile, outputFile, timeoutSeconds, exitCode] = process.argv.slice(2);

function fail(message) {
  console.error(message);
  process.exit(1);
}

function requireString(value, field) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    fail(`Release manifest is missing ${field}.`);
  }

  return value;
}

function immutableRef(image) {
  const ref = requireString(image?.ref, 'images.migration.ref');
  const digest = requireString(image?.digest, 'images.migration.digest');
  const version = requireString(manifest.release?.version, 'release.version');

  if (!/^sha256:[a-f0-9]{64}$/i.test(digest)) {
    fail('images.migration.digest must be sha256.');
  }

  return `${ref}:${version}@${digest}`;
}

const manifest = JSON.parse(fs.readFileSync(manifestFile, 'utf8'));
const output = fs.readFileSync(outputFile, 'utf8');
const migration = manifest.extensions?.migration ?? {};
const markers = Array.isArray(migration.successOutputMarkers)
  ? migration.successOutputMarkers
  : [
      'All migrations have been successfully applied.',
      'No pending migrations to apply.',
    ];
const matchedOutput = markers.find((marker) => output.includes(marker));

if (!matchedOutput) {
  fail('Migration output did not include a Prisma success marker.');
}

const releaseTag = requireString(manifest.release?.tag, 'release.tag');
const markerPath = migration.successMarkerPath ?? `releases/${releaseTag}.migration-success.json`;
const markerFile = path.isAbsolute(markerPath)
  ? markerPath
  : path.join(path.dirname(manifestFile), markerPath);
const payload = {
  schemaVersion: migration.successMarkerSchemaVersion ?? 1,
  status: 'succeeded',
  completedAt: new Date().toISOString(),
  release: {
    tag: releaseTag,
    version: requireString(manifest.release?.version, 'release.version'),
    commitSha: requireString(manifest.release?.commitSha, 'release.commitSha'),
    url: requireString(manifest.release?.url, 'release.url'),
  },
  deploy: {
    trigger: requireString(manifest.deploy?.trigger, 'deploy.trigger'),
  },
  migrationImage: immutableRef(manifest.images?.migration),
  databaseUrlEnvVar: migration.databaseUrlEnvVar ?? 'DATABASE_URL',
  timeoutSeconds: Number(timeoutSeconds),
  exitCode: Number(exitCode),
  matchedOutput,
};

fs.mkdirSync(path.dirname(markerFile), { recursive: true });
fs.writeFileSync(markerFile, `${JSON.stringify(payload, null, 2)}\n`);
console.log(`Wrote migration success marker: ${markerFile}`);
NODE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      [[ $# -ge 2 ]] || fail "Missing value for --env-file."
      ENV_FILE="$2"
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
    --timeout-seconds)
      [[ $# -ge 2 ]] || fail "Missing value for --timeout-seconds."
      TIMEOUT_SECONDS="$2"
      shift 2
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

command -v docker >/dev/null 2>&1 || fail "docker must be installed and on PATH."
command -v node >/dev/null 2>&1 || fail "node must be installed and on PATH."
command -v timeout >/dev/null 2>&1 || fail "timeout must be installed and on PATH."

ENV_FILE="$(resolve_path "$ENV_FILE")"
COMPOSE_FILE="$(resolve_path "$COMPOSE_FILE")"
MANIFEST_FILE="$(resolve_path "$MANIFEST_FILE")"

[[ -f "$ENV_FILE" ]] || fail "Env file not found: $ENV_FILE"
[[ -f "$COMPOSE_FILE" ]] || fail "Compose file not found: $COMPOSE_FILE"
[[ -f "$MANIFEST_FILE" ]] || fail "Release manifest file not found: $MANIFEST_FILE"

output_file="$(mktemp)"
cleanup() {
  rm -f "$output_file"
}
trap cleanup EXIT

note "Running backend migration service"
set +e
timeout "$TIMEOUT_SECONDS" docker compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  --profile migration \
  run \
  --rm \
  backend-migrate >"$output_file" 2>&1
exit_code=$?
set -e

print_sanitized_output "$output_file"

if [[ "$exit_code" -eq 124 ]]; then
  fail "Migration timed out after $TIMEOUT_SECONDS seconds."
fi

if [[ "$exit_code" -ne 0 ]]; then
  fail "Migration failed with exit code $exit_code."
fi

write_success_marker "$output_file" "$exit_code"
note "Migration completed successfully"
