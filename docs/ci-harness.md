# CI Harness

## Pull Request Checks

`.github/workflows/pr-checks.yml` runs on pull requests to `main`, pushes to `main`, and manual dispatch. It uses:

```yaml
permissions:
  contents: read
```

The stable required job names are:

- `validate`
- `action-security`

`validate` keeps the existing deploy-bundle checks: shell syntax, ShellCheck, Node syntax, actionlint, Node tests, generated CI env validation, release metadata validation, Docker Compose rendering, Nginx validation, preflight, and deploy dry-run. It also detects common Node.js and Python project files and runs standard checks when those stacks are present.

`action-security` runs `scripts/ci/check-actions-pinning.sh` in enforcing mode. The script exits non-zero when external `uses:` references are not pinned to full 40-character SHAs.

## Release Workflow

`.github/workflows/release.yml` runs on pushed tags matching:

```text
v*
```

Jobs:

- `verify-release-source`
- `build-release`
- `publish-release`

`build-release` depends on `verify-release-source`. `publish-release` depends on `build-release`, has `contents: write`, and targets the `production` environment. All other release jobs keep `contents: read`.

## Release Tag Verification

`scripts/ci/verify-release-tag-from-main.sh` reads `GITHUB_REF_NAME`, fetches `origin/main`, fetches the exact tag, resolves the tag commit, and checks whether that commit is an ancestor of `origin/main`.

This blocks:

```text
unchecked feature branch -> manual v1.2.3 tag -> release workflow -> production release
```

## Release Tag Creation

`.github/workflows/create-release-tag.yml` is the preferred release tag creation path. It accepts `version`, validates `vMAJOR.MINOR.PATCH`, checks out `main`, rejects existing tags, creates an annotated tag, and pushes it. The workflow needs `contents: write` only because it creates the tag.

For repositories with protected `v*` tag creation, configure `RELEASE_TAG_TOKEN` as a repository secret containing a trusted release maintainer token that can bypass the tag ruleset. The workflow falls back to `GITHUB_TOKEN` only for repositories where the default token is sufficient.

## GitHub Actions Hardening

`scripts/ci/check-actions-pinning.sh` scans `.github/workflows/` for `uses:` references. Local actions and `docker://` references are ignored. External action references must use a full 40-character commit SHA.

## Production Environment Protection

Configure the `production` environment with required reviewers, prevent self-review, and restrict deployment branches/tags to `main` and/or `v*`. Keep production secrets only in this environment. Pull request workflows must not receive production secrets and must not deploy.

If cloud deployment is added later, prefer OIDC with:

```yaml
permissions:
  id-token: write
  contents: read
```

## Secrets Handling

- Do not use production secrets in `pull_request` or `pull_request_target` workflows.
- Do not expose production secrets to untrusted branches or forked PRs.
- Put production secrets only in the protected `production` environment.
- Keep release verification and build jobs free of production secrets.
