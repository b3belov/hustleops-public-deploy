# Release Process

This repository uses protected `main` plus protected `vMAJOR.MINOR.PATCH` release tags to keep unchecked code out of releases. The expected path is:

```text
feature branch -> pull request -> CI/security checks -> code review approval -> merge to protected main -> create v* tag from main -> verify tag source -> build/release/publish
```

## Standard Release Flow

1. Open a pull request into `main`.
2. Wait for required checks, including `validate` and `action-security`.
3. Obtain the required reviewer and CODEOWNERS approvals.
4. Merge only after the branch is up to date with `main`.
5. Create the release tag with the `Create Release Tag` workflow.
6. Let the `Release` workflow verify that the tag commit is reachable from `origin/main`.
7. Approve the `production` environment gate before publishing release artifacts.

## Creating A Release Tag

Use GitHub Actions, not a local shell:

1. Open Actions.
2. Run `Create Release Tag`.
3. Enter a version such as `v1.2.3`.
4. The workflow checks out `main`, rejects an existing tag, creates an annotated tag, and pushes it.

The version must match `vMAJOR.MINOR.PATCH`. The release workflow also validates the checked-in release metadata before publishing release assets.

The workflow uses `RELEASE_TAG_TOKEN`, a repository secret containing a trusted release maintainer token, so it can create protected `v*` tags under the release tag ruleset.

## Why Local Tag Pushes Are Forbidden

A local tag can be created from an unchecked feature branch. Without verification, that tag could trigger a production release without PR review, required checks, or CODEOWNERS approval. The release workflow blocks this by resolving the pushed tag and requiring the tag commit to be an ancestor of `origin/main`.

## Release Verification

`scripts/ci/verify-release-tag-from-main.sh` runs before build or publish jobs. It fetches `origin/main`, fetches the exact release tag, resolves the tag to a commit, and runs an ancestry check:

```text
tag commit reachable from origin/main -> release may continue
tag commit not reachable from origin/main -> release fails immediately
```

`build-release` depends on `verify-release-source`, and `publish-release` depends on `build-release`, so publishing cannot continue after a failed source verification.

## Rollback Considerations

Roll back by selecting a previously reviewed and protected release record, restoring the matching release metadata and runtime references, validating the deploy bundle, and creating a new reviewed release if needed. Do not move old release tags. Immutable tags are audit records; a rollback should create a new reviewed state rather than rewriting history.

## Forbidden Release Paths

- direct push to main
- manual release tag from unchecked branch
- moving existing release tag
- deleting release tag
- deploying from pull request workflow
- deploying from non-main commit
- publishing before release tag verification succeeds
- exposing production secrets to pull request workflows
