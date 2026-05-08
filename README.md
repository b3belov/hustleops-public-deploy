# HustleOps Deployment

This repository contains the Docker Compose deployment bundle for HustleOps.
It uses published container images and does not require application source code or local image builds.
The HustleOps GHCR images are public and can be pulled without signing in.

## Requirements

- Docker Engine with Docker Compose v2
- Network access to `ghcr.io`
- `cosign` for release image signature verification
- `openssl` for generating deployment secrets

## Release

- Tag: `v0.1.1`
- Version: `0.1.1`

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

After pulling a newer public deploy repository release, run:

```bash
./scripts/deploy.sh update --env-file .env
```

The update flow syncs release-managed image and metadata values from `.env.example` into `.env`, runs preflight checks, captures a PostgreSQL backup, applies pending migrations, runs the idempotent bootstrap contract, recreates core application services, and prints service status. Operator-provided secrets in `.env` are preserved.

Use `--with-ancillary` only when n8n and OpenSearch Dashboards should be exposed publicly.

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

n8n and OpenSearch Dashboards are not exposed by default. Enable them only when those public surfaces are required:

```bash
COMPOSE_PROFILES=ancillary-public docker compose --env-file .env -f docker-compose.prod.yml up -d nginx-ancillary
```

## Rollback

Use the previous release entry under `releases/`, restore the matching image refs in `.env`, run preflight checks, and roll services forward or backward only after confirming database compatibility.
