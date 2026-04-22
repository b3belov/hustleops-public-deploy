# HustleOps Public Deploy

This repository contains the public production deployment payload for HustleOps.

It is a runtime-only deploy repository. Application source code does not live here. This repo contains the production Compose stack, mounted nginx config, environment template, and the host-path directory layout used for persistent state.

## Repository Contents

- `docker-compose.prod.yml` for the production stack
- `.env.example` with required environment variables
- `nginx/` with mounted nginx config files
- `data/` directory placeholders for host-mounted persistence
- `docs/RELEASE-RUNBOOK.md` with release, validation, and rollback notes

## What Persists On The Host

- `data/postgres/` for HustleOps PostgreSQL
- `data/n8n/postgres/` for n8n PostgreSQL
- `data/uploads/` for backend uploads, screenshots, and chat files

These remain host-mounted. Redis, OpenSearch, n8n state, and n8n Redis remain Docker named volumes.

## Quick Start

1. Copy `.env.example` to `.env`.
2. Replace every `change_me` value.
3. Replace any `__HUSTLEOPS_*__` placeholders if release automation has not already rendered them.
4. Validate the stack:

```bash
docker compose --env-file .env -f docker-compose.prod.yml config
docker run --rm \
  --add-host frontend:127.0.0.1 \
  --add-host backend:127.0.0.1 \
  --add-host n8n:127.0.0.1 \
  --add-host opensearch-dashboards:127.0.0.1 \
  -v "$PWD/nginx/nginx.conf:/etc/nginx/nginx.conf:ro" \
  -v "$PWD/nginx/security-headers.conf:/etc/nginx/security-headers.conf:ro" \
  nginx:1.27-alpine nginx -t
```

5. Start the stack:

```bash
docker compose --env-file .env -f docker-compose.prod.yml up -d
```

## Ports

- `80` for the main app entry point
- `5678` for n8n through nginx
- `5601` for OpenSearch Dashboards through nginx

## Release Automation

This repo is designed to be updated by release automation from the source repository. That automation can refresh runtime image references and add release metadata files such as `release-manifest.json`, `deployment/release-trigger.txt`, and `releases/<tag>.json`.

## Operators

See `docs/RELEASE-RUNBOOK.md` for validation, release, and rollback guidance.
