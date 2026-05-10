#!/usr/bin/env bash
set -euo pipefail

workflow_dir=".github/workflows"
sha_pattern='^[0-9a-fA-F]{40}$'
failures=()

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"
  printf '%s' "$value"
}

is_local_or_docker_action() {
  local reference="$1"

  [[ "$reference" == ./* || "$reference" == ../* || "$reference" == docker://* ]]
}

check_reference() {
  local file_path="$1"
  local line_number="$2"
  local reference="$3"

  if is_local_or_docker_action "$reference"; then
    return
  fi

  if [[ "$reference" != *@* ]]; then
    failures+=("${file_path}:${line_number}: ${reference} (missing @<sha>)")
    return
  fi

  local ref="${reference##*@}"

  if [[ ! "$ref" =~ $sha_pattern ]]; then
    failures+=("${file_path}:${line_number}: ${reference}")
  fi
}

if [[ ! -d "$workflow_dir" ]]; then
  echo "No ${workflow_dir} directory found; nothing to scan."
  exit 0
fi

while IFS= read -r -d '' workflow_file; do
  line_number=0

  # The loop only reads workflow files; check_reference writes to the failures array.
  # shellcheck disable=SC2094
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))

    if [[ "$line" =~ ^[[:space:]-]*uses:[[:space:]]*(.+)$ ]]; then
      reference="${BASH_REMATCH[1]}"
      reference="${reference%%#*}"
      reference="$(trim "$reference")"

      if [[ -n "$reference" ]]; then
        check_reference "$workflow_file" "$line_number" "$reference"
      fi
    fi
  done < "$workflow_file"
done < <(find "$workflow_dir" -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 | sort -z)

if (( ${#failures[@]} > 0 )); then
  echo "Unpinned GitHub Actions references found:" >&2
  printf '  - %s\n' "${failures[@]}" >&2
  echo "Pin external actions to full 40-character commit SHAs." >&2
  exit 1
fi

echo "All external GitHub Actions are pinned to full commit SHAs."
