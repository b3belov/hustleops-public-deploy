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

3. Run preflight checks:

   ```bash
   ./scripts/preflight.sh --env-file .env
   ```

4. Capture a PostgreSQL backup:

   ```bash
   ./scripts/backup-postgres.sh --env-file .env
   ```

5. Apply database migrations:

   ```bash
   ./scripts/run-migration.sh --env-file .env --timeout-seconds 600
   ```

6. Create the first admin account when deploying into an empty database:

   ```bash
   docker compose --env-file .env -f docker-compose.prod.yml --profile bootstrap run --rm backend-bootstrap
   ```

7. Start the application:

   ```bash
   docker compose --env-file .env -f docker-compose.prod.yml up -d backend frontend nginx
   ```

## Optional Services

n8n and OpenSearch Dashboards are not exposed by default. Enable them only when those public surfaces are required:

```bash
COMPOSE_PROFILES=ancillary-public docker compose --env-file .env -f docker-compose.prod.yml up -d nginx-ancillary
```

## Rollback

Use the previous release entry under `releases/`, restore the matching image refs in `.env`, run preflight checks, and roll services forward or backward only after confirming database compatibility.
