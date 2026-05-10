# Scripts

This folder contains deployment, release-validation, and CI helper scripts for the
HustleOps public deployment repository.

| Script | What it checks | What it does |
| --- | --- | --- |
| `backup-postgres.sh` | Checks that Docker is available, the env and Compose files exist, `POSTGRES_USER` and `POSTGRES_DB` are populated, and a release tag can be resolved from `--tag`, `release-manifest.json`, or `HUSTLEOPS_RELEASE_TAG`. It also verifies the produced backup is not empty. | Runs `pg_dump` against the `postgres` Compose service and writes a release-tagged custom-format dump under `backups/` by default. |
| `deploy.sh` | Checks required tools and files for each command. For setup/update it also checks release metadata, signatures, backups, migrations, bootstrap, and service startup through the helper scripts and Docker Compose. | Main operator entrypoint for `setup`, `update`, `start`, `stop`, `status`, `preflight`, `backup`, `migrate`, and `bootstrap`. It syncs release-managed env values from `.env.example` into `.env` during setup/update. |
| `make-ci-env.mjs` | Checks that the env template contains every CI replacement key it needs. | Generates a CI-safe env file from `.env.example`, replacing secrets and local-only values with deterministic test values. |
| `preflight.sh` | Checks required production env values, placeholder usage, secret lengths and formats, digest-pinned image refs, release metadata consistency, optional cosign signatures, optional image pulls, and Docker Compose renderability for core, migration, bootstrap, and ancillary profiles. | Runs the deploy safety gate before production migration/bootstrap/start operations. |
| `run-migration.sh` | Checks Docker, Node, `timeout`, env/Compose/manifest files, timeout value, migration container exit status, and expected Prisma success markers in migration output. | Runs the one-shot `backend-migrate` Compose service and writes a release-linked migration success marker only after a successful or no-op migration. |
| `update-from-contract.mjs` | Checks release contract schema version, tag/version alignment, commit SHA format, image set and immutable refs, sha256 digests, linux/amd64 platform, pinned trust issuer and certificate identity, required trust artifacts, runtime facts, and migration requirements. | Converts a verified release contract into repo-local release files: `.env.example` image values, `release-manifest.json`, `release-verification.json`, `deployment/release-trigger.txt`, `releases/<tag>.json`, signature plan, and PR body. |
| `validate-nginx.sh` | Checks Docker availability, `nginx/security-headers.conf`, `nginx/nginx.conf`, and `nginx/nginx.ancillary.conf`. Each config is rendered with `nginx -t` in the pinned unprivileged Nginx image. | Validates both public Nginx configurations without requiring the full stack to be running. |
| `validate-release-metadata.mjs` | Checks that `.env`, `release-manifest.json`, `release-verification.json`, `deployment/release-trigger.txt`, and `releases/<tag>.json` agree on release tag/version, trigger, image refs, digests, immutable refs, commit SHA, and signature trust metadata. | Prints a release metadata validation result and can emit a tab-separated image signature verification plan for `cosign`. |

The GitHub validation workflows currently run shell syntax checks, ShellCheck,
Node syntax checks, release metadata validation with a generated CI env, Nginx
config validation, preflight with signature and pull checks skipped, and a deploy
dry run.
