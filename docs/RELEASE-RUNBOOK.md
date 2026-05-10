# Release Runbook

## Source Of Truth

- The application source repository owns application code, image publication, and the canonical release handoff contract.
- This public repository owns the runtime deployment payload: `docker-compose.prod.yml`, mounted nginx config files, host-path directory placeholders under `data/`, and future release metadata.

## What A Release Updates

1. Runtime image references for backend and frontend.
2. The deploy payload files in this repository.
3. Release metadata such as `release-manifest.json`, `deployment/release-trigger.txt`, and `releases/<tag>.json`.
4. A public deploy GitHub Release after the update PR lands on `main`, with `releases/<tag>.json` attached as the public contract.

## Validation

Validate the deploy payload before rollout:

```bash
docker compose --env-file .env -f docker-compose.prod.yml config
./scripts/validate-nginx.sh
```

## Persistence Layout

- `data/postgres/` stores HustleOps PostgreSQL data on the host.
- `data/n8n/postgres/` stores n8n PostgreSQL data on the host.
- `data/uploads/` stores backend uploads, screenshots, and chat files on the host.
- Redis, OpenSearch, n8n state, n8n PostgreSQL, and n8n Redis use host bind mounts under `data/`.

## Rollback

- Roll back to a prior release by restoring the earlier image references and release metadata.
- Use `releases/<tag>.json`, or the matching public deploy GitHub Release asset, as the immutable record for the previous rollout.
- Re-run validation before bringing the stack back up.
