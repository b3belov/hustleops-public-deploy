# GitHub Workflows

This folder contains the GitHub Actions workflows that validate the public
deployment bundle, update it from a verified HustleOps release contract, and
enforce the protected `main` plus `v*` release-tag harness.

| Workflow | Trigger | What it checks | What it does |
| --- | --- | --- | --- |
| `pr-checks.yml` (`Pull Request Checks`) | Pull requests to `main`, pushes to `main`, and manual `workflow_dispatch` runs. | Runs detected Node/Python checks when project manifests exist, repeats deploy-bundle validation, and enforces GitHub Actions pinning. | Provides stable required status check names: `validate` and `action-security`. |
| `validate.yml` (`Validate Deploy Bundle`) | Pull requests, pushes to `main`, and manual `workflow_dispatch` runs. | Checks shell syntax, ShellCheck, Node syntax, GitHub Actions syntax with `actionlint`, generated CI env values, release metadata consistency, Docker Compose rendering for core/migration/bootstrap/ancillary profiles, both Nginx configs, `preflight.sh` in CI mode, and `deploy.sh update` as a dry run. | Provides the main CI safety gate for changes to deploy scripts, metadata, Compose config, Nginx config, and release files. |
| `update-from-contract.yml` (`Update From Release Contract`) | Manual `workflow_dispatch` with a `contract-ref` input. | Checks the release contract OCI digest and cosign signature against the pinned GitHub Actions issuer and certificate identity pattern, validates contract schema/trust/runtime/image facts through `update-from-contract.mjs`, verifies runtime image signatures, then repeats script syntax, ShellCheck, Node syntax, `actionlint`, release metadata, Compose, Nginx, preflight, and deploy dry-run checks. | Pulls a verified release contract, updates repo release artifacts, pushes an automation branch, and opens or updates the public deploy update PR when generated files changed. |
| `create-release-tag.yml` (`Create Release Tag`) | Manual `workflow_dispatch` with a `version` input. | Validates `vMAJOR.MINOR.PATCH` and rejects existing tags. | Creates an annotated `v*` release tag from the current `main` commit. |
| `release.yml` (`Release`) | Pushes to `v*` tags. | Verifies the tag commit is reachable from `origin/main`, validates release metadata, and builds release notes before publication. | Publishes the protected GitHub Release only after source verification, build validation, and `production` environment approval. |
| `ruleset-audit.yml` (`Ruleset Audit`) | Manual `workflow_dispatch` and weekly schedule. | Lists repository rulesets through GitHub CLI. | Provides read-only visibility into GitHub-side ruleset configuration. |

These workflows pin external GitHub Actions to full commit SHAs and use Node.js
24 for the repository's JavaScript validation helpers.
