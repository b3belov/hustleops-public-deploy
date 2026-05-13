#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
DAYS=825

usage() {
  cat <<'EOF'
Usage: ./scripts/setup-nginx-self-signed-cert.sh [--env-file PATH] [--days DAYS]

Generate a self-signed certificate for the public nginx HTTPS listener.
The certificate SANs are built from PUBLIC_HOSTNAME plus PUBLIC_HOST_ALIASES.
EOF
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

trim() {
  local value="$1"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

resolve_path() {
  local value="$1"

  if [[ "$value" = /* ]]; then
    printf '%s\n' "$value"
    return
  fi

  printf '%s\n' "$PROJECT_ROOT/${value#./}"
}

read_env_value() {
  local key="$1"
  local line value

  [[ -f "$ENV_FILE" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" == "$key="* ]] || continue
    value="${line#*=}"
    if [[ "$value" =~ ^\".*\"$ || "$value" =~ ^\'.*\'$ ]]; then
      value="${value:1:${#value}-2}"
    fi
    printf '%s\n' "$value"
    return 0
  done < "$ENV_FILE"
}

is_ip_address() {
  local value="$1"

  [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ || "$value" == *:* ]]
}

append_name() {
  local value="$1"
  local existing

  value="$(trim "$value")"
  [[ -n "$value" ]] || return 0

  if [[ "$HOST_NAMES_COUNT" -gt 0 ]]; then
    for existing in "${HOST_NAMES[@]}"; do
      [[ "$existing" == "$value" ]] && return 0
    done
  fi

  HOST_NAMES+=("$value")
  HOST_NAMES_COUNT=$((HOST_NAMES_COUNT + 1))
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      [[ $# -ge 2 ]] || fail "Missing value for --env-file."
      ENV_FILE="$2"
      shift 2
      ;;
    --days)
      [[ $# -ge 2 ]] || fail "Missing value for --days."
      [[ "$2" =~ ^[0-9]+$ ]] || fail "--days must be a positive integer."
      DAYS="$2"
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

command -v openssl >/dev/null 2>&1 || fail "openssl must be installed and on PATH."
[[ -f "$ENV_FILE" ]] || fail "Env file not found: $ENV_FILE"

PUBLIC_HOSTNAME="$(read_env_value PUBLIC_HOSTNAME)"
PUBLIC_HOST_ALIASES="$(read_env_value PUBLIC_HOST_ALIASES)"
NGINX_TLS_CERT_PATH="$(read_env_value NGINX_TLS_CERT_PATH)"
NGINX_TLS_KEY_PATH="$(read_env_value NGINX_TLS_KEY_PATH)"

[[ -n "$PUBLIC_HOSTNAME" ]] || fail "PUBLIC_HOSTNAME is required to generate a self-signed nginx certificate."
[[ -n "$NGINX_TLS_CERT_PATH" ]] || NGINX_TLS_CERT_PATH="./nginx/certs/fullchain.pem"
[[ -n "$NGINX_TLS_KEY_PATH" ]] || NGINX_TLS_KEY_PATH="./nginx/certs/privkey.pem"

CERT_FILE="$(resolve_path "$NGINX_TLS_CERT_PATH")"
KEY_FILE="$(resolve_path "$NGINX_TLS_KEY_PATH")"
CERT_DIR="$(dirname "$CERT_FILE")"
KEY_DIR="$(dirname "$KEY_FILE")"

HOST_NAMES=()
HOST_NAMES_COUNT=0
append_name "$PUBLIC_HOSTNAME"
if [[ -n "$PUBLIC_HOST_ALIASES" ]]; then
  IFS=',' read -ra ALIASES <<< "$PUBLIC_HOST_ALIASES"
  for alias in "${ALIASES[@]}"; do
    append_name "$alias"
  done
fi

mkdir -p "$CERT_DIR" "$KEY_DIR"
CONFIG_FILE="$(mktemp)"
trap 'rm -f "$CONFIG_FILE"' EXIT

{
  printf '[req]\n'
  printf 'default_bits = 2048\n'
  printf 'prompt = no\n'
  printf 'default_md = sha256\n'
  printf 'distinguished_name = dn\n'
  printf 'x509_extensions = v3_req\n'
  printf '\n[dn]\n'
  printf 'CN = %s\n' "$PUBLIC_HOSTNAME"
  printf '\n[v3_req]\n'
  printf 'subjectAltName = @alt_names\n'
  printf '\n[alt_names]\n'
  dns_index=1
  ip_index=1
  for host_name in "${HOST_NAMES[@]}"; do
    if is_ip_address "$host_name"; then
      printf 'IP.%s = %s\n' "$ip_index" "$host_name"
      ip_index=$((ip_index + 1))
    else
      printf 'DNS.%s = %s\n' "$dns_index" "$host_name"
      dns_index=$((dns_index + 1))
    fi
  done
} > "$CONFIG_FILE"

openssl req \
  -x509 \
  -nodes \
  -newkey rsa:2048 \
  -days "$DAYS" \
  -keyout "$KEY_FILE" \
  -out "$CERT_FILE" \
  -config "$CONFIG_FILE" >/dev/null 2>&1

chmod 0644 "$CERT_FILE"
chmod 0644 "$KEY_FILE"

printf 'Generated nginx self-signed certificate:\n'
printf '  Certificate: %s\n' "$CERT_FILE"
printf '  Private key: %s\n' "$KEY_FILE"
printf '  Names:\n'
for host_name in "${HOST_NAMES[@]}"; do
  printf '    - %s\n' "$host_name"
done
