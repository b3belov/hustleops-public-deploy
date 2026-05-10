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
- Require approval of latest push
- Require review from Code Owners
- Require required status checks
- Require branch to be up to date before merge
- Block force pushes
- Block branch deletion
- Restrict bypass permissions

Recommended required status checks:

- `validate`
- `action-security`

Enable `Require review from Code Owners`. `.github/CODEOWNERS` currently uses the repository admin account because no organization teams were visible through the GitHub API; replace it with real teams after trusted maintainer teams exist.

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
- Allow tag creation only from the release workflow or trusted release maintainers

Manual local tag pushes should be blocked for normal developers. The preferred path is the `Create Release Tag` workflow, which creates annotated tags from the current `main` commit.

The `Create Release Tag` workflow uses a repository secret named `RELEASE_TAG_TOKEN`, backed by a trusted release maintainer token that can bypass the `v*` tag ruleset. Keep this token scoped to the release-maintainer account and rotate it if release ownership changes.

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

The `publish-release` job targets this environment so release publication waits for explicit approval when the environment protection rule is enabled.

## Acceptance Checks

- Direct push to `main` is rejected.
- Pull requests cannot merge without required checks.
- Pull requests cannot merge without required approvals.
- Pull requests touching CODEOWNERS paths require CODEOWNER approval.
- Force pushes and branch deletion for `main` are rejected.
- Untrusted users cannot create, move, or delete `v*` tags.
- Release tags outside `main` history fail in the release workflow.
