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
- `approve-production-release`
- `publish-release`

`build-release` depends on `verify-release-source`. `approve-production-release` depends on `build-release` and runs only for manual dispatch. `publish-release` depends on both `build-release` and `approve-production-release`, runs only for manual dispatch, has `contents: write`, and targets the `production` environment. All other release jobs keep `contents: read`.

## Release Tag Verification

`scripts/ci/verify-release-tag-from-main.sh` reads `RELEASE_TAG` first, then `GITHUB_REF_NAME`, rejects empty names, `main`, and non-`vMAJOR.MINOR.PATCH` tags, fetches `origin/main`, fetches the exact tag, resolves the tag commit, and checks whether that commit is an ancestor of `origin/main`.

This blocks:

```text
unchecked feature branch -> manual v1.2.3 tag -> release workflow -> production release
```

## Release Tag Creation

`.github/workflows/create-release-tag.yml` is the preferred release tag creation path. It accepts `version`, validates `vMAJOR.MINOR.PATCH`, checks out `main` with persisted credentials disabled, verifies `RELEASE_TAG_APPROVER`, rejects existing tags, creates an annotated tag, and pushes it with a dedicated release-tag GitHub App token. The workflow keeps `contents: read` for the default `GITHUB_TOKEN`; only the App installation token receives `contents: write` for the tag push.

For repositories with protected `v*` tag creation, configure `RELEASE_TAG_APP_ID` as a repo or org variable and `RELEASE_TAG_APP_PRIVATE_KEY` as a repository secret for a dedicated GitHub App that is allowed to create release tags. Configure `RELEASE_TAG_APPROVER` as a repo or org variable containing the GitHub username allowed to request release tag creation.

## GitHub Actions Hardening

`scripts/ci/check-actions-pinning.sh` scans `.github/workflows/` for `uses:` references. Local actions and `docker://` references are ignored. External action references must use a full 40-character commit SHA.

## Ruleset Audit

`.github/workflows/ruleset-audit.yml` runs weekly and on manual dispatch. Its stable job name is `audit-rulesets`. It uses the default `GITHUB_TOKEN` as `GH_TOKEN` and lists repository rulesets with:

```bash
gh api "repos/${GITHUB_REPOSITORY}/rulesets" --jq '.[] | {name, target, enforcement, bypass_actors, conditions}'
```

This is a read-only audit/reporting check. It does not replace configuring branch and tag rulesets in GitHub.

## Production Environment Protection

Configure the `production` environment with required reviewers, prevent self-review, and restrict deployment branches/tags to `main` and/or `v*`. Keep production secrets only in this environment. Pull request workflows must not receive production secrets and must not deploy.

Configure `PRODUCTION_RELEASE_APPROVER` and `PRODUCTION_DEPLOYMENT_APPROVER` as repo or org variables. Manual release publication and manual deployment fail closed when the relevant variable is missing or does not match `GITHUB_ACTOR`.

## Production Deployment

`.github/workflows/deploy.yml` is manual-only. It builds and validates the deploy bundle first, verifies `PRODUCTION_DEPLOYMENT_APPROVER`, then runs the production deploy job on a self-hosted runner labeled `production` and attached to the `production` environment.

The deploy job uses the real operator command:

```bash
./scripts/deploy.sh update --env-file "$PRODUCTION_ENV_FILE" --yes
```

Use `release_ref=main` only for the protected branch head, or use a protected `vMAJOR.MINOR.PATCH` tag that is reachable from `origin/main`. Keep the production env file and production runtime secrets on the protected environment or target host, not in pull request workflows.

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
- Keep release-tag GitHub App private keys separate from production runtime secrets.
- Configure `PUBLIC_DEPLOY_UPDATE_DEPLOY_KEY` only if the manual `Update From Release Contract` workflow should be able to push automation update branches.
