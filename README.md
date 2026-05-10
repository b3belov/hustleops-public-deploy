# HustleOps Deployment

This repository contains the Docker Compose deployment bundle for HustleOps.
It uses published container images and does not require application source code or local image builds.
The HustleOps GHCR images are public and can be pulled without signing in.

## Requirements

- Docker Engine with Docker Compose v2
- Node.js 24 or newer for local validation scripts
- Network access to `ghcr.io`
- `cosign` for release image signature verification
- `openssl` for generating deployment secrets
- GNU `timeout` for non-dry-run migration/update flows. On macOS, install with `brew install coreutils` and ensure `timeout` is on `PATH`.

## Setup

1. Create the deployment environment file:

   ```bash
   cp .env.example .env
   ```

2. Replace every `change_me` value in `.env`. The comments in `.env.example` include generation commands for required secrets.

3. Confirm the host directories under `data/` and `logs/` are writable by the matching containers before first start. Logs continue to use Docker stdout by default; use `logs/<service>/` only when file logging is intentionally enabled and shipped off-host.

4. Run the setup flow:

   ```bash
   ./scripts/deploy.sh setup --env-file .env
   ```

   The setup flow validates required tools, verifies release images, captures a PostgreSQL backup, applies migrations, runs the initial-admin bootstrap, and starts the core application services.

## Update

Repository maintainers can update this deployment bundle from a signed release contract before operators pull it:

1. Run the `Update From Release Contract` GitHub Actions workflow.
2. Keep the default contract ref for the latest release, or enter a specific `ghcr.io/hustleops/hustleops-release-contract:<version>` ref.
3. Review and merge the generated update PR after CI passes.

The workflow verifies the contract signature before reading the JSON payload, cross-checks the verified payload trust fields, verifies runtime image signatures, updates `.env.example`, records root and immutable release metadata, and validates the deploy scripts, Compose files, and nginx configs. After the generated update PR is merged to `main`, the `Publish Public Release` workflow creates or updates the matching public deploy GitHub Release and attaches the public contract metadata.

After pulling a newer public deploy repository release, run:

```bash
./scripts/deploy.sh update --env-file .env
```

The update flow syncs release-managed image and metadata values from `.env.example` into `.env`, runs preflight checks, captures a PostgreSQL backup, applies pending migrations, runs the idempotent bootstrap contract, recreates core application services, and prints service status. Operator-provided secrets in `.env` are preserved.

Use `--with-ancillary` only when n8n and OpenSearch Dashboards should be exposed through the ancillary reverse proxy.

## Local Validation

Before opening a PR or applying a manual config change:

```bash
node scripts/make-ci-env.mjs --output /tmp/hustleops-ci.env
node scripts/validate-release-metadata.mjs --env-file /tmp/hustleops-ci.env
docker compose --env-file /tmp/hustleops-ci.env -f docker-compose.prod.yml config >/dev/null
docker compose --env-file /tmp/hustleops-ci.env -f docker-compose.prod.yml --profile ancillary-public config >/dev/null
./scripts/validate-nginx.sh
./scripts/preflight.sh --env-file /tmp/hustleops-ci.env --skip-pull --skip-signature-verify
```

## Manual Operations

The unified deploy script calls these lower-level scripts internally. Operators can still run them directly when diagnosing a failed rollout:

```bash
./scripts/preflight.sh --env-file .env
./scripts/backup-postgres.sh --env-file .env
./scripts/run-migration.sh --env-file .env --timeout-seconds 600
```

Manual bootstrap and service start commands:

```bash
docker compose --env-file .env -f docker-compose.prod.yml --profile bootstrap run --rm backend-bootstrap
docker compose --env-file .env -f docker-compose.prod.yml up -d backend frontend nginx
```

## Optional Services

n8n and OpenSearch Dashboards bind to localhost by default. Enable them only when those surfaces are required:

```bash
COMPOSE_PROFILES=ancillary-public docker compose --env-file .env -f docker-compose.prod.yml up -d nginx-ancillary
```

`--with-ancillary` publishes n8n on port `5678` and OpenSearch Dashboards on port `5601`.
Only use non-localhost `ANCILLARY_N8N_BIND` or `ANCILLARY_DASHBOARDS_BIND` values behind a trusted network boundary such as VPN, private firewall rules, SSO-capable reverse proxy, or equivalent access control.

## Rollback

Use the previous release entry under `releases/`, restore the matching image refs in `.env`, run preflight checks, and roll services forward or backward only after confirming database compatibility.
