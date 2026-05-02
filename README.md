# HustleOps Deployment

This repository contains the Docker Compose deployment bundle for HustleOps.
It uses published container images and does not require application source code or local image builds.

## Requirements

- Docker Engine with Docker Compose v2
- Access to the published HustleOps GHCR images
- `cosign` for release image signature verification
- `openssl` for generating deployment secrets

## Release

- Tag: `v0.1.1`
- Version: `0.1.1`

## Setup

1. Authenticate to GHCR:

   ```bash
   echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USERNAME" --password-stdin
   ```

2. Create the deployment environment file:

   ```bash
   cp .env.example .env
   ```

3. Replace every `change_me` value in `.env`. The comments in `.env.example` include generation commands for required secrets.

4. Run preflight checks:

   ```bash
   ./scripts/preflight.sh --env-file .env
   ```

5. Capture a PostgreSQL backup:

   ```bash
   ./scripts/backup-postgres.sh --env-file .env
   ```

6. Apply database migrations:

   ```bash
   ./scripts/run-migration.sh --env-file .env --timeout-seconds 600
   ```

7. Create the first admin account when deploying into an empty database:

   ```bash
   docker compose --env-file .env -f docker-compose.prod.yml --profile bootstrap run --rm backend-bootstrap
   ```

8. Start the application:

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
