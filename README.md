# HustleOps Public Deploy

This repository is the public production deployment source for HustleOps.
Deployment consumes published runtime images only.
No source bundle or local Docker build context is required for deployment.

## Contract

- Backend, frontend, and migration deploy refs pin immutable image digests in `.env.example`.
- Run database migrations explicitly before starting updated app containers.
- Use `./scripts/run-migration.sh --env-file .env --timeout-seconds 600` once per release; inject the database URL through `DATABASE_URL` from .env POSTGRES_USER, POSTGRES_PASSWORD, and POSTGRES_DB values rendered into docker-compose.prod.yml service environment.
- Migration timeout contract is 600s and fail if docker compose run --rm exceeds timeoutSeconds or exits non-zero.
- Success means exit code 0 plus one of: `All migrations have been successfully applied.` or `No pending migrations to apply.`.
- Store the release-linked migration success marker at `releases/v0.1.1.migration-success.json` beside `releases/v0.1.1.json`; same-release reruns stay safe-to-rerun-same-release under a single-runner owner model with idempotent retries.
- Success marker release linkage is `v0.1.1`, `release-v0.1.1-2777278c1275`, `release-manifest.json`, and `release-verification.json`.
- `docker-compose.prod.yml` and the mounted nginx config files live in the same repository and directory tree.
- Backend user uploads persist on the repository host path `data/uploads/`.
- Main and n8n postgres data persist on the repository host paths under `data/`.
- Immutable release provenance lives in `release-manifest.json`, `release-verification.json`, and `releases/`.
- `deployment/release-trigger.txt` changes every release so `latest` publishes still produce a deterministic rollout diff.
- Public ingress uses nginxinc/nginx-unprivileged:1.27-alpine@sha256:65e3e85dbaed8ba248841d9d58a899b6197106c23cb0ff1a132b7bfe0547e4c0 with mounted config files from `nginx/`; app ingress stays on port `80` and ancillary public surfaces stay behind the optional `ancillary-public` profile.
- Ancillary public surfaces stay disabled unless COMPOSE_PROFILES=ancillary-public is set.
- Production defaults to stdout-first logging; set `HUSTLEOPS_FORCE_STDOUT_LOGGING=false` only when you have a deliberate writable log-volume plan.
- Run `./scripts/preflight.sh --env-file .env` after populating `.env` to fail fast on invalid secrets, signature verification failures, inaccessible images, or compose-profile drift before migration.
- Operators should treat `release-verification.json` as the verification source of truth for immutable image digests.

## Writable Path Matrix

| Path | Owner expectation | Purpose | Write source | Failure mode |
| --- | --- | --- | --- | --- |
| `data/uploads/` -> `/app/uploads` | Host path must grant write access to backend UID `1000` | Persistent attachments and chat uploads | Backend runtime | Attachment writes fail with `EACCES` or `EROFS` |
| Backend `/tmp` tmpfs | Container-managed tmpfs, writable to the backend runtime user | Runtime scratch space and `HOME=/tmp` | Backend runtime and break-glass diagnostics | Runtime scratch writes fail with `EROFS` and debug scripts cannot persist temp files |
| `data/postgres/` -> `/var/lib/postgresql/data` | Host path writable by the postgres container user | Primary HustleOps database state | `postgres` service | Postgres cannot initialize or persist WAL/data files |
| `data/n8n/postgres/` -> `/var/lib/postgresql/data` | Host path writable by the n8n postgres container user | n8n database state | `n8n-postgres` service | n8n metadata DB cannot initialize or persist state |
| `redis_data:/data` | Docker-managed volume | Redis append-only persistence | `redis` service | Redis durability degrades and restarts lose buffered state |
| `opensearch_data:/usr/share/opensearch/data` | Docker-managed volume | Search indices and cluster metadata | `opensearch` service | Search cluster becomes unhealthy or loses indexed data |
| `n8n_data:/home/node/.n8n` | Docker-managed volume | n8n workflows, credentials, and execution metadata | `n8n` service | n8n state resets between restarts |
| `n8n_redis_data:/data` | Docker-managed volume | n8n queue broker state | `n8n-redis` service | Queue state is lost across restarts |
| Nginx `/tmp`, `/var/cache/nginx`, and `/run` tmpfs | Container-managed tmpfs writable to UID `101` | Nginx temp files, cache, and runtime PID state | `frontend`, `nginx`, and `nginx-ancillary` services | Nginx fails to start or reload cleanly |

## Logging Contract

- Default production mode is stdout-first: keep `HUSTLEOPS_FORCE_STDOUT_LOGGING=true` unless you have an explicit writable log-volume exception.
- File logging is opt-in only. If operators disable the stdout-first guardrail, they must provide a dedicated writable log path and keep retention bounded by the `logging.file.maxSize` and `logging.file.maxFiles` system settings.
- Do not point application file logging at the container root filesystem. Use a separate host path or managed volume owned for the backend runtime user.
- Log retention and export are operator responsibilities once file logging is enabled. Rotate and ship logs off-host before disk usage reaches the configured service thresholds.
- Redaction expectations do not change when file logging is enabled: passwords, tokens, API keys, and other live credentials must stay out of logs and release artifacts.

## Operational Guardrails

- Before launch, confirm stdout logs are shipped off-host, retained for the incident-response window, and searchable by release tag, container name, request correlation ID, and severity. If file logging is enabled, document the writable path, shipper, retention limit, and rotation owner.
- Disk monitoring must cover `data/postgres/`, `data/n8n/postgres/`, `data/uploads/`, Docker-managed volumes, and the backup output directory. Stop the rollout if free-space thresholds or alert routing are missing for any persistent path.
- If production traffic terminates TLS or reverse proxying outside this compose bundle, document the external proxy owner and config. The proxy must preserve `/api/`, `/socket.io/`, websocket upgrade headers, request size limits for uploads, and an exact `CORS_ORIGIN` match for the public frontend origin.
- Keep the rollback owner, escalation path, and incident channel in the rollout notes before tagging. App-only rollback uses immutable image digests from the previous `releases/*.json` entry and is allowed only when schema compatibility is confirmed; incompatible migrations require restore-from-backup or roll-forward handling.

## Compatibility Checklist

- Backend steady-state runtime is the shell-free image `ghcr.io/hustleops/hustleops-backend@sha256:da2b3b06485f0bd01c82dae00ab795eb8e68f619f13139379c92c0c128f8d22c`; health probes and debug entrypoints must use `/nodejs/bin/node`, not shell-based commands.
- Migration and one-shot bootstrap remain explicit tooling exceptions via `ghcr.io/hustleops/hustleops-backend-migrate@sha256:d7e866a1b3646caa815e73b43a591342da66b3d51a39244c108b04758caaedda`; that image carries Prisma CLI plus the compiled bootstrap payload, while the steady-state backend image stays free of `dist/prisma` tooling files.
- Published backend, frontend, and migration images are pinned to `linux/amd64`; arm64 operators need x86_64 emulation available before rollout.
- Frontend runtime stays on `nginxinc/nginx-unprivileged:1.27-alpine@sha256:65e3e85dbaed8ba248841d9d58a899b6197106c23cb0ff1a132b7bfe0547e4c0`; nginx validation still relies on `nginx -t` and the mounted `nginx/` configs.
- Backend native dependencies and Prisma engines are built against the Debian/glibc runtime family used by the steady-state image. Rebuild and revalidate if the base family changes.
- Backend runtime assumes writable `/tmp` tmpfs and a writable uploads mount at `/app/uploads`; removing either path causes the negative-path checks to fail closed.
- Required executables in the production contract are `/nodejs/bin/node` for backend health and diagnostics, `nginx` for frontend and edge validation, `pg_isready` for postgres, `redis-cli` for Redis, and `curl` inside the OpenSearch image healthcheck.
- No shell is available in the shipped steady-state backend image. Use the documented break-glass diagnostic path instead of trying to `exec` a shell into production containers.

## Break-Glass Debug Path

- Keep the production image immutable and shell-free. Do not swap the backend image base or relax `read_only` just to debug an incident.
- Use a time-bounded diagnostic script mounted into an ephemeral one-off backend companion, then delete the script after the investigation.
- Example flow:
  ```bash
  mkdir -p debug
  cat > debug/backend-diagnostic.mjs <<'EOF'
  import { readdir } from 'node:fs/promises';
  console.log(await readdir('/app/uploads'));
  EOF
  docker run --rm \
    --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,nodev,size=64m \
    --env-file .env \
    --network <compose-app-network> \
    -v "$PWD/debug/backend-diagnostic.mjs:/tmp/backend-diagnostic.mjs:ro" \
    -v "$PWD/data/uploads:/app/uploads:rw" \
    --entrypoint /nodejs/bin/node \
    ghcr.io/hustleops/hustleops-backend@sha256:da2b3b06485f0bd01c82dae00ab795eb8e68f619f13139379c92c0c128f8d22c /tmp/backend-diagnostic.mjs
  rm -f debug/backend-diagnostic.mjs
  ```
- Replace `<compose-app-network>` with the active app network name from the running deployment. Keep the debug container short-lived and never commit the diagnostic script into the deploy repository.

## Current Release

- Tag: v0.1.1
- Version: 0.1.1
- Release URL: https://github.com/HustleOps/HustleOps/releases/tag/v0.1.1
- Deploy trigger: release-v0.1.1-2777278c1275

## Rollout

1. Authenticate to GHCR before pulling pinned digests:
   ```bash
   echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USERNAME" --password-stdin
   ```
2. Verify all release digests before copying `.env.example` into `.env`:
   ```bash
   cosign verify --certificate-identity "https://github.com/HustleOps/HustleOps/.github/workflows/release.yml@refs/tags/v0.1.1" --certificate-oidc-issuer "https://token.actions.githubusercontent.com" "ghcr.io/hustleops/hustleops-backend@sha256:da2b3b06485f0bd01c82dae00ab795eb8e68f619f13139379c92c0c128f8d22c"
   cosign verify --certificate-identity "https://github.com/HustleOps/HustleOps/.github/workflows/release.yml@refs/tags/v0.1.1" --certificate-oidc-issuer "https://token.actions.githubusercontent.com" "ghcr.io/hustleops/hustleops-frontend@sha256:8a2ddfb1b8624a5e4cbb6f07493968f2da0f4c3e58e1343c7c1df76a490880f5"
   cosign verify --certificate-identity "https://github.com/HustleOps/HustleOps/.github/workflows/release.yml@refs/tags/v0.1.1" --certificate-oidc-issuer "https://token.actions.githubusercontent.com" "ghcr.io/hustleops/hustleops-backend-migrate@sha256:d7e866a1b3646caa815e73b43a591342da66b3d51a39244c108b04758caaedda"
   ```
3. Copy `.env.example` to `.env`, replace every placeholder value, then run the operator preflight contract:
   ```bash
   ./scripts/preflight.sh --env-file .env
   ```
4. Capture a release-tagged database backup before migration:
   ```bash
   ./scripts/backup-postgres.sh --env-file .env
   ```
5. Run the one-shot migration contract and stop if it fails:
   ```bash
   ./scripts/run-migration.sh --env-file .env --timeout-seconds 600
   ```
6. The migration helper writes `releases/v0.1.1.migration-success.json` when the command exits 0 and matches one of the expected success outputs:
   ```json
{
  "schemaVersion": 1,
  "status": "succeeded",
  "completedAt": "<RFC3339 timestamp>",
  "release": {
    "tag": "v0.1.1",
    "version": "0.1.1",
    "commitSha": "2777278c1275038fd1dd1afabbdc15f17e1536f0",
    "url": "https://github.com/HustleOps/HustleOps/releases/tag/v0.1.1"
  },
  "deploy": {
    "trigger": "release-v0.1.1-2777278c1275"
  },
  "migrationImage": "ghcr.io/hustleops/hustleops-backend-migrate@sha256:d7e866a1b3646caa815e73b43a591342da66b3d51a39244c108b04758caaedda",
  "databaseUrlEnvVar": "DATABASE_URL",
  "exitCode": 0,
  "matchedOutput": "All migrations have been successfully applied."
}
   ```
7. Roll out app services with `docker compose --env-file .env -f docker-compose.prod.yml up -d backend frontend nginx`.
8. Enable ancillary public surfaces only when explicitly needed via `COMPOSE_PROFILES=ancillary-public`.

## Rollback

- Restore the prior approved `releases/<tag>.json`, `release-verification.json`, and digest-pinned image refs together.
- App-only rollback is safe only when the target release is schema-compatible.
- If the current release already applied an incompatible migration, restore the database from backup or roll forward with a fixed release instead of swapping app containers alone.

## Validation

docker compose --env-file .env.example -f docker-compose.prod.yml config
docker compose --env-file .env.example -f docker-compose.prod.yml --profile ancillary-public config
docker run --rm -v "$PWD/nginx/nginx.conf:/etc/nginx/nginx.conf:ro" -v "$PWD/nginx/security-headers.conf:/etc/nginx/security-headers.conf:ro" --add-host frontend:127.0.0.1 --add-host backend:127.0.0.1 nginxinc/nginx-unprivileged:1.27-alpine@sha256:65e3e85dbaed8ba248841d9d58a899b6197106c23cb0ff1a132b7bfe0547e4c0 nginx -t
docker run --rm -v "$PWD/nginx/nginx.ancillary.conf:/etc/nginx/nginx.conf:ro" -v "$PWD/nginx/security-headers.conf:/etc/nginx/security-headers.conf:ro" --add-host n8n:127.0.0.1 --add-host opensearch-dashboards:127.0.0.1 nginxinc/nginx-unprivileged:1.27-alpine@sha256:65e3e85dbaed8ba248841d9d58a899b6197106c23cb0ff1a132b7bfe0547e4c0 nginx -t
