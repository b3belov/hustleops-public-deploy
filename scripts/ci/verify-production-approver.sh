#!/usr/bin/env bash
set -euo pipefail

expected_approver="${1:-}"
actor="${GITHUB_ACTOR:-}"

if [[ -z "$expected_approver" ]]; then
  echo "Expected production approver argument is required." >&2
  exit 2
fi

if [[ -z "$actor" ]]; then
  echo "GITHUB_ACTOR is required." >&2
  exit 2
fi

if [[ "$actor" != "$expected_approver" ]]; then
  echo "GITHUB_ACTOR ${actor} does not match expected approver ${expected_approver}." >&2
  exit 1
fi

echo "Verified production approver ${actor}."
