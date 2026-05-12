# Branch And Tag Protection

Committed files provide CI, release verification, CODEOWNERS, templates, and documentation. They do not protect the repository by themselves. A repository admin must configure GitHub rulesets and the production environment.

## Main Branch Ruleset

Target:

```text
refs/heads/main
```

Required settings:

- Require pull request before merging
- Require at least 1 approval
- Dismiss stale approvals
- Require required status checks
- Require branch to be up to date before merge
- Block force pushes
- Block branch deletion
- Restrict bypass permissions

Recommended required status checks:

- `validate`
- `action-security`

Team-maintained ideal:

- Require review from Code Owners.
- Require approval of the most recent push.

Solo-maintainer practical mode:

- Keep `.github/CODEOWNERS` as advisory documentation for operations/security ownership.
- For now, do not require both `Require review from Code Owners` and `Require approval of the most recent push`.
- Disable either `Require review from Code Owners` or `Require approval of the most recent push` so a one-person repository can still merge protected `.github/` and CI/CD changes.
- Treat this as a temporary operational tradeoff. Re-enable both controls after a second trusted maintainer or team exists.

## Release Tag Ruleset

Target:

```text
refs/tags/v*
```

Required settings:

- Protect `v*` tags
- Restrict tag creation
- Restrict tag updates
- Restrict tag deletion
- Block force pushes
- Block moving tags
- Allow tag creation only from trusted release maintainers or the dedicated release-tag GitHub App

Manual local tag pushes should be blocked for normal developers. The preferred path is the `Create Release Tag` workflow, which creates annotated tags from the current `main` commit.

The `Create Release Tag` workflow uses a dedicated GitHub App installation token to push protected `v*` tags. Configure the tag ruleset bypass list so only that release-tag App, or explicitly trusted release maintainers, can create protected release tags.

Set this repo or org variable:

```text
RELEASE_TAG_APPROVER
RELEASE_TAG_APP_ID
```

`RELEASE_TAG_APPROVER` must match the GitHub username allowed to run release tag creation. `RELEASE_TAG_APP_ID` must identify the dedicated release-tag GitHub App.

Set this repository secret:

```text
RELEASE_TAG_APP_PRIVATE_KEY
```

Rotate the App private key if release ownership changes and do not reuse it for production runtime access.

## Production Environment

Create a GitHub Environment:

```text
production
```

Required settings:

- Required reviewers
- Prevent self-review
- Restrict deployment branches/tags to `main` and/or `v*`
- Store production secrets only in this environment

The `publish-release` job targets this environment so release publication waits for explicit approval when the environment protection rule is enabled. Required environment reviewers should be enabled whenever available. The explicit approver script remains in the workflow as a fallback and extra gate.

Set these repo or org variables:

```text
PRODUCTION_RELEASE_APPROVER
PRODUCTION_DEPLOYMENT_APPROVER
```

`PRODUCTION_RELEASE_APPROVER` is used by the release publication gate. `PRODUCTION_DEPLOYMENT_APPROVER` is used by the manual production deploy gate.

The `Deploy App` workflow uses `PRODUCTION_DEPLOYMENT_APPROVER`, then waits on
the `production` environment before running on a self-hosted runner labeled
`production`. Keep production runtime secrets and the production env file out of
pull request workflows.

## Acceptance Checks

- Direct push to `main` is rejected.
- Pull requests cannot merge without required checks.
- Pull requests cannot merge without required approvals.
- Pull requests touching CODEOWNERS paths require CODEOWNER approval when Code Owners review is enabled.
- Force pushes and branch deletion for `main` are rejected.
- Untrusted users cannot create, move, or delete `v*` tags.
- Release tags outside `main` history fail in the release workflow.
- Manual release publication fails when `PRODUCTION_RELEASE_APPROVER` is missing or does not match the actor.
- Manual release tag creation fails when `RELEASE_TAG_APPROVER` is missing or does not match the actor.
- Manual production deployment fails when `PRODUCTION_DEPLOYMENT_APPROVER` is missing or does not match the actor.
