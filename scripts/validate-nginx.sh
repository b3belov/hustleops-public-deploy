#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NGINX_IMAGE="nginxinc/nginx-unprivileged:1.30-alpine@sha256:808f7846d21a9c94cf53833e8807a00a33fd0b65cc47fb05b79efe366c2d201f"
TLS_TMP_DIR=""

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

validate_config() {
  local config_file="$1"

  [[ -f "$PROJECT_ROOT/$config_file" ]] || fail "nginx config not found: $config_file"

  docker run --rm \
    --add-host frontend:127.0.0.1 \
    --add-host backend:127.0.0.1 \
    --add-host n8n:127.0.0.1 \
    --add-host opensearch-dashboards:127.0.0.1 \
    -v "$PROJECT_ROOT/$config_file:/etc/nginx/nginx.conf:ro" \
    -v "$PROJECT_ROOT/nginx/security-headers-no-csp.conf:/etc/nginx/security-headers-no-csp.conf:ro" \
    -v "$PROJECT_ROOT/nginx/security-headers.conf:/etc/nginx/security-headers.conf:ro" \
    -v "$TLS_TMP_DIR/fullchain.pem:/etc/nginx/tls/fullchain.pem:ro" \
    -v "$TLS_TMP_DIR/privkey.pem:/etc/nginx/tls/privkey.pem:ro" \
    "$NGINX_IMAGE" nginx -t
}

command -v docker >/dev/null 2>&1 || fail "docker must be installed and on PATH."
command -v openssl >/dev/null 2>&1 || fail "openssl must be installed and on PATH."
[[ -f "$PROJECT_ROOT/nginx/security-headers-no-csp.conf" ]] || fail "nginx no-CSP security headers config not found."
[[ -f "$PROJECT_ROOT/nginx/security-headers.conf" ]] || fail "nginx security headers config not found."

TLS_TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TLS_TMP_DIR"' EXIT

openssl req -x509 \
  -nodes \
  -newkey rsa:2048 \
  -days 1 \
  -subj "/CN=hustleops.local" \
  -addext "subjectAltName=DNS:hustleops.local,IP:127.0.0.1" \
  -keyout "$TLS_TMP_DIR/privkey.pem" \
  -out "$TLS_TMP_DIR/fullchain.pem" >/dev/null 2>&1

validate_config "nginx/nginx.conf"
validate_config "nginx/nginx.ancillary.conf"
