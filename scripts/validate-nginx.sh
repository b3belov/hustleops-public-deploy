#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NGINX_IMAGE="nginxinc/nginx-unprivileged:1.27-alpine@sha256:65e3e85dbaed8ba248841d9d58a899b6197106c23cb0ff1a132b7bfe0547e4c0"

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
    "$NGINX_IMAGE" nginx -t
}

command -v docker >/dev/null 2>&1 || fail "docker must be installed and on PATH."
[[ -f "$PROJECT_ROOT/nginx/security-headers-no-csp.conf" ]] || fail "nginx no-CSP security headers config not found."
[[ -f "$PROJECT_ROOT/nginx/security-headers.conf" ]] || fail "nginx security headers config not found."

validate_config "nginx/nginx.conf"
validate_config "nginx/nginx.ancillary.conf"
