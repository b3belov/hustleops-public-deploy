#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.prod.yml"
MANIFEST_FILE="$PROJECT_ROOT/release-manifest.json"
VERIFICATION_FILE="$PROJECT_ROOT/release-verification.json"
SKIP_PULL=0
SKIP_SIGNATURE_VERIFY=0

usage() {
  cat <<'EOF'
Usage: ./scripts/preflight.sh [--env-file PATH] [--compose-file PATH] [--manifest-file PATH] [--verification-file PATH] [--skip-pull] [--skip-signature-verify]

Validate populated deployment env, image signatures, digest-pinned image refs,
and compose profiles before running migration/bootstrap in production.
EOF
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

note() {
  printf '==> %s\n' "$*"
}

resolve_path() {
  local value="$1"

  if [[ "$value" = /* ]]; then
    printf '%s\n' "$value"
    return
  fi

  printf '%s\n' "$PWD/${value#./}"
}

normalize_value() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c '[:alnum:]' '_'
}

contains_placeholder() {
  local normalized
  normalized="$(normalize_value "$1")"
  [[ "$normalized" == *change_me* || "$normalized" == *placeholder* || "$1" == __*__ ]]
}

trim() {
  local value="$1"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

load_env_file() {
  local line key value

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line//[[:space:]]/}" ]]; then
      continue
    fi

    key="$(trim "${line%%=*}")"
    value="$(trim "${line#*=}")"

    if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      fail "Invalid env line in $ENV_FILE: $line"
    fi

    if [[ "$value" =~ ^".*"$ || "$value" =~ ^'.*'$ ]]; then
      value="${value:1:${#value}-2}"
    fi

    export "$key=$value"
  done < "$ENV_FILE"
}

require_var() {
  local name="$1"
  local value="${!name-}"

  [[ -n "$value" ]] || fail "$name is required in $ENV_FILE."
}

require_non_placeholder() {
  local name="$1"
  local value="${!name}"

  if contains_placeholder "$value"; then
    fail "$name must not use placeholder values."
  fi
}

validate_min_length() {
  local name="$1"
  local minimum="$2"
  local value="${!name}"

  [[ ${#value} -ge $minimum ]] || fail "$name must be at least $minimum characters long."
}

validate_hex_64() {
  local name="$1"
  local value="${!name}"

  [[ "$value" =~ ^[0-9a-fA-F]{64}$ ]] || fail "$name must be exactly 64 hexadecimal characters."
}

validate_digest_ref() {
  local name="$1"
  local value="${!name}"

  [[ "$value" =~ :[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-fA-F]{64}$ ]] || fail "$name must include the release version tag and sha256 digest."
}

validate_cors_origin() {
  local value="$CORS_ORIGIN"

  [[ "$value" =~ ^https?:// ]] || fail "CORS_ORIGIN must start with http:// or https://."
  [[ "$value" != *example.com* ]] || fail "CORS_ORIGIN must not use example.com placeholder hostnames."
  if contains_placeholder "$value"; then
    fail "CORS_ORIGIN must not use placeholder values."
  fi
}

validate_bootstrap_email() {
  local value="${BOOTSTRAP_ADMIN_EMAIL-}"

  [[ -z "$value" ]] && return
  [[ "$value" == *"@"* ]] || fail "BOOTSTRAP_ADMIN_EMAIL must look like an email address."
  if contains_placeholder "$value"; then
    fail "BOOTSTRAP_ADMIN_EMAIL must not use placeholder values."
  fi
}

validate_env() {
  local required_plain=(
    POSTGRES_PASSWORD
    REDIS_PASSWORD
    OPENSEARCH_ADMIN_PASSWORD
    N8N_POSTGRES_PASSWORD
    N8N_REDIS_PASSWORD
    N8N_ENCRYPTION_KEY
    N8N_RUNNERS_AUTH_TOKEN
    HUSTLEOPS_RELEASE_TAG
    HUSTLEOPS_RELEASE_TRIGGER
  )
  local digest_refs=(
    HUSTLEOPS_BACKEND_IMAGE
    HUSTLEOPS_FRONTEND_IMAGE
    HUSTLEOPS_BACKEND_MIGRATION_IMAGE
  )
  local name

  for name in "${required_plain[@]}"; do
    require_var "$name"
    require_non_placeholder "$name"
  done

  for name in "${digest_refs[@]}"; do
    require_var "$name"
    require_non_placeholder "$name"
    validate_digest_ref "$name"
  done

  require_var JWT_ACCESS_SECRET
  require_var JWT_REFRESH_SECRET
  require_var TWO_FACTOR_ENCRYPTION_KEY
  require_var BOOTSTRAP_ADMIN_PASSWORD
  require_var CORS_ORIGIN

  require_non_placeholder JWT_ACCESS_SECRET
  require_non_placeholder JWT_REFRESH_SECRET
  require_non_placeholder TWO_FACTOR_ENCRYPTION_KEY
  require_non_placeholder BOOTSTRAP_ADMIN_PASSWORD

  validate_min_length JWT_ACCESS_SECRET 32
  validate_min_length JWT_REFRESH_SECRET 32
  [[ "$JWT_ACCESS_SECRET" != "$JWT_REFRESH_SECRET" ]] || fail "JWT access and refresh secrets must differ."

  validate_hex_64 TWO_FACTOR_ENCRYPTION_KEY
  validate_min_length BOOTSTRAP_ADMIN_PASSWORD 16
  validate_cors_origin
  validate_bootstrap_email
}

run_pull_checks() {
  note "Pulling pinned release images"
  docker pull --platform linux/amd64 "$HUSTLEOPS_BACKEND_IMAGE" >/dev/null
  docker pull --platform linux/amd64 "$HUSTLEOPS_FRONTEND_IMAGE" >/dev/null
  docker pull --platform linux/amd64 "$HUSTLEOPS_BACKEND_MIGRATION_IMAGE" >/dev/null
}

build_signature_plan() {
  node - \
    "$MANIFEST_FILE" \
    "$VERIFICATION_FILE" \
    "$HUSTLEOPS_BACKEND_IMAGE" \
    "$HUSTLEOPS_FRONTEND_IMAGE" \
    "$HUSTLEOPS_BACKEND_MIGRATION_IMAGE" <<'NODE'
const fs = require('node:fs');

const [
  manifestFile,
  verificationFile,
  backendImage,
  frontendImage,
  migrationImage,
] = process.argv.slice(2);

function fail(message) {
  console.error(message);
  process.exit(1);
}

function readJson(filePath, label) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (error) {
    fail(`Could not parse ${label}: ${error instanceof Error ? error.message : String(error)}`);
  }
}

function requireString(value, field) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    fail(`Release verification is missing ${field}.`);
  }

  return value;
}

function immutableRef(image, imageKey) {
  const ref = requireString(image?.ref, `manifest image ${imageKey}.ref`);
  const digest = requireString(
    image?.digest,
    `manifest image ${imageKey}.digest`,
  );
  const version = requireString(manifest.release?.version, 'release.version');

  if (!/^sha256:[a-f0-9]{64}$/i.test(digest)) {
    fail(`Manifest image ${imageKey} digest must be sha256.`);
  }

  if (Array.isArray(image?.tags) && !image.tags.includes(version)) {
    fail(`Manifest image ${imageKey} tags must include ${version}.`);
  }

  return `${ref}:${version}@${digest}`;
}

const manifest = readJson(manifestFile, 'release manifest');
const verification = readJson(verificationFile, 'release verification');
const trustPolicy = verification.trustPolicy ?? {};
const certificateIdentity = requireString(
  trustPolicy.certificateIdentity,
  'trustPolicy.certificateIdentity',
);
const issuer = requireString(trustPolicy.issuer, 'trustPolicy.issuer');
const expectedImages = {
  backend: {
    envName: 'HUSTLEOPS_BACKEND_IMAGE',
    envValue: backendImage,
  },
  frontend: {
    envName: 'HUSTLEOPS_FRONTEND_IMAGE',
    envValue: frontendImage,
  },
  migration: {
    envName: 'HUSTLEOPS_BACKEND_MIGRATION_IMAGE',
    envValue: migrationImage,
  },
};

for (const field of ['tag', 'version', 'commitSha']) {
  if (manifest.release?.[field] !== verification.release?.[field]) {
    fail(`Release verification mismatch for ${field}.`);
  }
}

for (const [imageKey, expected] of Object.entries(expectedImages)) {
  const manifestImage = manifest.images?.[imageKey];
  const verificationImage = verification.images?.[imageKey];

  if (!manifestImage) {
    fail(`Release manifest is missing image entry for ${imageKey}.`);
  }

  if (!verificationImage) {
    fail(`Release verification is missing image entry for ${imageKey}.`);
  }

  const expectedRef = immutableRef(manifestImage, imageKey);
  if (verificationImage.immutableRef !== expectedRef) {
    fail(`Release verification immutable image mismatch for ${imageKey}.`);
  }

  if (verificationImage.digest !== manifestImage.digest) {
    fail(`Release verification digest mismatch for ${imageKey}.`);
  }

  if (expected.envValue !== expectedRef) {
    fail(`${expected.envName} must match ${imageKey} immutable image from release verification.`);
  }

  const signature = verificationImage.verification?.signature ?? {};
  if (signature.certificateIdentity !== certificateIdentity) {
    fail(`Signature identity mismatch for ${imageKey}.`);
  }

  if (signature.issuer !== issuer) {
    fail(`Signature issuer mismatch for ${imageKey}.`);
  }

  console.log(`${expectedRef}\t${certificateIdentity}\t${issuer}`);
}
NODE
}

run_signature_checks() {
  local verification_plan image_ref certificate_identity issuer

  note "Verifying release image signatures"
  if ! verification_plan="$(build_signature_plan)"; then
    fail "Release verification metadata check failed."
  fi

  while IFS=$'\t' read -r image_ref certificate_identity issuer; do
    [[ -n "$image_ref" ]] || continue
    if ! cosign verify \
      --certificate-identity "$certificate_identity" \
      --certificate-oidc-issuer "$issuer" \
      "$image_ref" >/dev/null; then
      fail "Signature verification failed for $image_ref."
    fi
  done <<< "$verification_plan"
}

run_compose_checks() {
  note "Rendering compose config"
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" config >/dev/null
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" --profile migration config >/dev/null
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" --profile bootstrap config >/dev/null
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" --profile ancillary-public config >/dev/null
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
    --verification-file)
      [[ $# -ge 2 ]] || fail "Missing value for --verification-file."
      VERIFICATION_FILE="$2"
      shift 2
      ;;
    --skip-pull)
      SKIP_PULL=1
      shift
      ;;
    --skip-signature-verify)
      SKIP_SIGNATURE_VERIFY=1
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

ENV_FILE="$(resolve_path "$ENV_FILE")"
COMPOSE_FILE="$(resolve_path "$COMPOSE_FILE")"
MANIFEST_FILE="$(resolve_path "$MANIFEST_FILE")"
VERIFICATION_FILE="$(resolve_path "$VERIFICATION_FILE")"

[[ -f "$ENV_FILE" ]] || fail "Env file not found: $ENV_FILE"
[[ -f "$COMPOSE_FILE" ]] || fail "Compose file not found: $COMPOSE_FILE"

load_env_file
validate_env

command -v docker >/dev/null 2>&1 || fail "docker must be installed and on PATH."

if [[ $SKIP_SIGNATURE_VERIFY -eq 0 ]]; then
  command -v node >/dev/null 2>&1 || fail "node must be installed and on PATH for signature verification."
  command -v cosign >/dev/null 2>&1 || fail "cosign must be installed and on PATH, or pass --skip-signature-verify."
  [[ -f "$MANIFEST_FILE" ]] || fail "Release manifest file not found: $MANIFEST_FILE"
  [[ -f "$VERIFICATION_FILE" ]] || fail "Release verification file not found: $VERIFICATION_FILE"
fi

if [[ $SKIP_SIGNATURE_VERIFY -eq 0 ]]; then
  run_signature_checks
else
  note "Skipping signature verification (--skip-signature-verify)"
fi

if [[ $SKIP_PULL -eq 0 ]]; then
  run_pull_checks
else
  note "Skipping image pulls"
fi

run_compose_checks
note "Preflight checks passed"
