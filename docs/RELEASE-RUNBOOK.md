# Release Runbook

## Source Of Truth

- The application source repository owns application code, image publication, and the canonical release handoff contract.
- This public repository owns the runtime deployment payload: `docker-compose.prod.yml`, mounted nginx config files, host-path directory placeholders under `data/`, and future release metadata.

## What A Release Updates

1. Runtime image references for backend and frontend.
2. The deploy payload files in this repository.
3. Release metadata such as `release-manifest.json`, `deployment/release-trigger.txt`, and `releases/<tag>.json` when automation is enabled.

## Validation

Validate the deploy payload before rollout:

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

## Persistence Layout

- `data/postgres/` stores HustleOps PostgreSQL data on the host.
- `data/n8n/postgres/` stores n8n PostgreSQL data on the host.
- `data/uploads/` stores backend uploads, screenshots, and chat files on the host.
- Redis, OpenSearch, n8n state, and n8n Redis use Docker named volumes defined in Compose.

## Rollback

- Roll back to a prior release by restoring the earlier image references and release metadata.
- If your release automation writes `releases/<tag>.json`, use that file as the immutable record for the previous rollout.
- Re-run validation before bringing the stack back up.
