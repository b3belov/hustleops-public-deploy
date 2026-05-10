# GitHub Workflows

This folder contains the GitHub Actions workflows that validate the public
deployment bundle and update it from a verified HustleOps release contract.

| Workflow | Trigger | What it checks | What it does |
| --- | --- | --- | --- |
| `validate.yml` (`Validate Deploy Bundle`) | Pull requests, pushes to `main`, and manual `workflow_dispatch` runs. | Checks shell syntax, ShellCheck, Node syntax, GitHub Actions syntax with `actionlint`, generated CI env values, release metadata consistency, Docker Compose rendering for core/migration/bootstrap/ancillary profiles, both Nginx configs, `preflight.sh` in CI mode, and `deploy.sh update` as a dry run. | Provides the main CI safety gate for changes to deploy scripts, metadata, Compose config, Nginx config, and release files. |
| `update-from-contract.yml` (`Update From Release Contract`) | Manual `workflow_dispatch` with a `contract-ref` input. | Checks the release contract OCI digest and cosign signature against the pinned GitHub Actions issuer and certificate identity pattern, validates contract schema/trust/runtime/image facts through `update-from-contract.mjs`, verifies runtime image signatures, then repeats script syntax, ShellCheck, Node syntax, `actionlint`, release metadata, Compose, Nginx, preflight, and deploy dry-run checks. | Pulls a verified release contract, updates repo release artifacts, pushes an automation branch, and opens or updates the public deploy update PR when generated files changed. |
| `publish-release.yml` (`Publish Public Release`) | Pushes to `main` that update release metadata and manual `workflow_dispatch` runs. | Checks the public release notes generator, generated CI env values, and release metadata consistency before publishing. | Creates or updates the GitHub Release for the checked-in release tag and uploads `release-manifest.json`, `release-verification.json`, and the immutable `releases/<tag>.json` public contract. |

These workflows use pinned third-party actions where configured and Node.js 24 for
the repository's JavaScript validation helpers.
