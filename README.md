# HustleOps Public Deploy

This repository is the public production deployment source for HustleOps.

## Contract

- Backend and frontend stay on mutable `latest` tags for rollout parity with the approved release flow.
- `docker-compose.prod.yml` and the mounted nginx config files live in the same repository and directory tree.
- Backend user uploads persist on the repository host path `data/uploads/`.
- Main and n8n postgres data persist on the repository host paths under `data/`.
- Immutable release provenance lives in `release-manifest.json` and `releases/`.
- `deployment/release-trigger.txt` changes every release so `latest` publishes still produce a deterministic rollout diff.
- Public ingress uses the stock nginx image with mounted config files from `nginx/` and serves ports `80`, `5678`, and `5601`.

## Current Release

- Tag: v0.0.5
- Version: 0.0.5
- Release URL: https://github.com/b3belov/HustleOps/releases/tag/v0.0.5
- Deploy trigger: release-v0.0.5-0f99f4628808

## Validation

docker compose --env-file .env.example -f docker-compose.prod.yml config
docker run --rm --add-host frontend:127.0.0.1 --add-host backend:127.0.0.1 --add-host n8n:127.0.0.1 --add-host opensearch-dashboards:127.0.0.1 -v "$PWD/nginx/nginx.conf:/etc/nginx/nginx.conf:ro" -v "$PWD/nginx/security-headers.conf:/etc/nginx/security-headers.conf:ro" nginx:1.27-alpine nginx -t
