#!/usr/bin/env bash
set -euo pipefail

tag_name="${RELEASE_TAG:-${GITHUB_REF_NAME:-}}"

if [[ -z "$tag_name" ]]; then
  echo "RELEASE_TAG or GITHUB_REF_NAME is required and must contain the release tag name." >&2
  exit 2
fi

if [[ "$tag_name" == "main" ]]; then
  echo "Release tag name must not be main." >&2
  exit 2
fi

if [[ ! "$tag_name" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Release tag ${tag_name} must match vMAJOR.MINOR.PATCH, for example v1.2.3." >&2
  exit 2
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "This script must run inside a git work tree." >&2
  exit 2
fi

git fetch --no-tags --prune origin +refs/heads/main:refs/remotes/origin/main
git fetch --no-tags --force origin "+refs/tags/${tag_name}:refs/tags/${tag_name}"

tag_commit="$(git rev-parse "refs/tags/${tag_name}^{commit}")"
main_commit="$(git rev-parse "refs/remotes/origin/main^{commit}")"

if git merge-base --is-ancestor "$tag_commit" "$main_commit"; then
  echo "Release tag ${tag_name} is reachable from origin/main."
  echo "tag_commit=${tag_commit}"
  echo "origin_main=${main_commit}"
  exit 0
fi

echo "Release tag ${tag_name} is not reachable from origin/main." >&2
echo "tag_commit=${tag_commit}" >&2
echo "origin_main=${main_commit}" >&2
exit 1
