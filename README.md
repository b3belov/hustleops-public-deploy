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

   The setup flow validates required tools, verifies release images, captures a PostgreSQL backup, applies migrations, runs the initial-admin bootstrap, starts the core application services, starts n8n and OpenSearch Dashboards, exposes their ancillary proxy ports, prints Docker Compose status, and prints service access addresses.

## Update

Repository maintainers can update this deployment bundle from a signed release contract before operators pull it:

1. Run the `Update From Release Contract` GitHub Actions workflow.
2. Keep the default contract ref for the latest release, or enter a specific `ghcr.io/hustleops/hustleops-release-contract:<version>` ref.
3. Review and merge the generated update PR after CI passes.

The workflow verifies the contract signature before reading the JSON payload, cross-checks the verified payload trust fields, verifies runtime image signatures, updates `.env.example`, records root and immutable release metadata, and validates the deploy scripts, Compose files, and nginx configs. After the generated update PR is merged to `main`, the `Release Public Deploy` workflow publishes the next independent `public-deploy-vX.Y.Z` release for this repository and attaches the current public contract metadata. Direct changes to this repository also create a new public deploy release, even when the source application version is unchanged.

After pulling a newer public deploy repository release, run:

```bash
./scripts/deploy.sh update --env-file .env
```

The update flow syncs release-managed image and metadata values from `.env.example` into `.env`, runs preflight checks, captures a PostgreSQL backup, applies pending migrations, runs the idempotent bootstrap contract, recreates core application services, starts n8n and OpenSearch Dashboards, publishes their ancillary proxy ports, and prints service status plus access addresses. Operator-provided secrets in `.env` are preserved.

n8n and OpenSearch Dashboards start by default and are exposed through the ancillary reverse proxy. Use `--skip-ancillary` when those ports must not be published, and use `--skip-n8n` when the n8n runtime itself should not be started.

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

## Published Services

The default start path publishes:

- HustleOps app: port `80`
- n8n: port `5678`
- OpenSearch Dashboards: port `5601`

After startup, `deploy.sh` prints service access addresses. Set `PUBLIC_HOSTNAME` in `.env` so the deploy script prints concrete service addresses after startup. If `PUBLIC_HOSTNAME` is empty, the script prints `server-ip-or-dns` as a reminder to use the target host address.

`ANCILLARY_N8N_BIND` and `ANCILLARY_DASHBOARDS_BIND` default to `0.0.0.0`. Restrict these values to a private interface when the host is not already protected by trusted network boundaries such as VPN, private firewall rules, SSO-capable reverse proxy, or equivalent access control.

`--debug` leaves Docker image pull progress visible and enables shell tracing for deploy/preflight diagnostics.

## Starting and Stopping

Start the full stack after it was stopped or brought down:

```bash
./scripts/deploy.sh start --env-file .env
```

Restart the full stack:

```bash
./scripts/deploy.sh restart --env-file .env
```

Stop services (containers remain, data is preserved):

```bash
./scripts/deploy.sh stop --env-file .env
```

Bring down containers and networks entirely (data volumes are preserved):

```bash
./scripts/deploy.sh down --env-file .env
```

## Rollback

Use the previous release entry under `releases/`, restore the matching image refs in `.env`, run preflight checks, and roll services forward or backward only after confirming database compatibility.
