#!/usr/bin/env bash
# setup-dind.sh — Shadow bind-mount source paths for Docker-in-Docker environments.
#
# In dev container environments where the project root is backed by a fakeowner
# FUSE filesystem (e.g. Docker Desktop host sharing on macOS/Windows), the Docker
# daemon cannot bind-mount paths from that filesystem.  This script detects that
# condition and replaces each bind-mount source path with a symlink to a native
# filesystem location, allowing the Docker daemon to resolve and mount them.
#
# Safe to run multiple times — already-symlinked paths are skipped.
# Requires passwordless sudo for creating directories under /var/local/.
#
# Usage:
#   ./scripts/setup-dind.sh [--project-root PATH] [--native-base PATH] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NATIVE_BASE="/var/local/hustleops"
DRY_RUN=0
VERBOSE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root)
      [[ $# -ge 2 ]] || { echo "Missing value for --project-root" >&2; exit 1; }
      PROJECT_ROOT="$2"; shift 2 ;;
    --native-base)
      [[ $# -ge 2 ]] || { echo "Missing value for --native-base" >&2; exit 1; }
      NATIVE_BASE="$2"; shift 2 ;;
    --dry-run)
      DRY_RUN=1; shift ;;
    --verbose)
      VERBOSE=1; shift ;;
    *)
      echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# Only needed in fakeowner (Docker Desktop host-sharing) environments.
if ! grep -q 'fakeowner' /proc/mounts 2>/dev/null; then
  [[ "$VERBOSE" -eq 1 ]] && echo "Not in a fakeowner environment — nothing to do."
  exit 0
fi

echo "fakeowner filesystem detected — setting up native bind-mount shadows."

# ---------------------------------------------------------------------------
# All bind-mount source paths from docker-compose.prod.yml.
# Format: "dir:<relative-path>" or "file:<relative-path>"
# ---------------------------------------------------------------------------
BIND_SOURCES=(
  # Data directories — contain persistent state; existing contents are copied.
  "dir:data/postgres"
  "dir:data/redis"
  "dir:data/opensearch"
  "dir:data/opensearch-dashboards"
  "dir:data/uploads"
  "dir:data/n8n/postgres"
  "dir:data/n8n/redis"
  "dir:data/n8n/app"

  # Log directories — ephemeral; created empty.
  "dir:logs/postgres"
  "dir:logs/redis"
  "dir:logs/opensearch"
  "dir:logs/opensearch-dashboards"
  "dir:logs/backend"
  "dir:logs/backend-migrate"
  "dir:logs/backend-bootstrap"
  "dir:logs/frontend"
  "dir:logs/nginx"
  "dir:logs/nginx-ancillary"
  "dir:logs/n8n-postgres"
  "dir:logs/n8n-redis"
  "dir:logs/n8n"
  "dir:logs/n8n-worker"
  "dir:logs/task-runner-main"
  "dir:logs/task-runner-worker"

  # nginx config files — read-only mounts; copied to native filesystem.
  "file:nginx/nginx.conf"
  "file:nginx/security-headers-no-csp.conf"
  "file:nginx/security-headers.conf"
  "file:nginx/nginx.ancillary.conf"
)

shadow_dir() {
  local rel_path="$1"
  local source="$PROJECT_ROOT/$rel_path"
  local native="$NATIVE_BASE/$rel_path"

  if [[ -L "$source" ]]; then
    [[ "$VERBOSE" -eq 1 ]] && echo "  [skip] $rel_path (already a symlink)"
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [dry-run] would shadow dir: $rel_path -> $native"
    return 0
  fi

  sudo mkdir -p "$native"

  # Copy existing contents to the native location (preserving ownership/perms).
  if [[ -d "$source" ]] && [[ -n "$(ls -A "$source" 2>/dev/null)" ]]; then
    echo "  Copying $rel_path -> $native"
    sudo cp -a "$source/." "$native/"
  fi

  rm -rf "$source"
  ln -sfn "$native" "$source"
  echo "  Shadowed $rel_path -> $native"
}

shadow_file() {
  local rel_path="$1"
  local source="$PROJECT_ROOT/$rel_path"
  local native="$NATIVE_BASE/$rel_path"

  if [[ -L "$source" ]]; then
    [[ "$VERBOSE" -eq 1 ]] && echo "  [skip] $rel_path (already a symlink)"
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [dry-run] would shadow file: $rel_path -> $native"
    return 0
  fi

  sudo mkdir -p "$(dirname "$native")"

  if [[ -f "$source" ]]; then
    sudo cp "$source" "$native"
  else
    sudo touch "$native"
  fi

  rm -f "$source"
  ln -sfn "$native" "$source"
  echo "  Shadowed $rel_path -> $native"
}

for entry in "${BIND_SOURCES[@]}"; do
  type="${entry%%:*}"
  rel_path="${entry#*:}"

  case "$type" in
    dir)  shadow_dir  "$rel_path" ;;
    file) shadow_file "$rel_path" ;;
    *)    echo "Unknown entry type: $type" >&2; exit 1 ;;
  esac
done

echo "Done. All bind-mount source paths are now backed by native filesystem entries."
