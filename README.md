# Sonora

Sonora is a private, invite-only music streaming web app. The repository is a pnpm monorepo with these parts: `apps/api`, `modules/*`, `packages/config`, and `infra/*`. Everything runs in Docker through `docker compose`. On the host you need only Docker and `make`.

This file is a contract for the local development environment. Later steps build it. Nothing here is a claim that the stack already works.

## First run

1. Copy the example environment file: `cp .env.example .env`
2. Open `.env` and fill in the required keys (see [Environment file](#environment-file)).
3. Start the stack and load the seed data: `make up && make seed`

`make up` checks `.env` first. If a required key is empty, it stops with a clear message.

## Make targets

| Target | What it does |
| --- | --- |
| `make up` | Checks `.env`, builds and starts mysql, redis, s3, mailpit, traefik, api and media-worker, and waits until every container is healthy. |
| `make doctor` | Asserts that every container above reports healthy within 120 seconds, prints a table, and exits non-zero otherwise. |
| `make seed` | Loads the Creative Commons tracks listed in `infra/seed/manifest.json` into the S3 `originals` bucket, idempotently, and writes `seed-report.json`. |
| `make migrate` | Applies the Prisma migrations to the database. |
| `make test` | Runs the repository checks and tests inside the workspace container. |
| `make logs s=<service>` | Follows the logs of one service, for example `make logs s=api`. |
| `make down` | Stops the containers. |
| `make down-v` | Stops the containers and removes volumes. |
| `make check-databases` | Verifies that each module user can use only its own database. |

## Services

| Name | What it is | How to reach it |
| --- | --- | --- |
| mysql | MySQL 8.4, holds the module databases | Docker network only. This contract does not define a host port. |
| redis | Redis 7.4 | Docker network only. This contract does not define a host port. |
| s3 | Adobe S3Mock, an S3 emulator with buckets `originals`, `renditions` and `artwork` | `s3.sonora.localhost` through Traefik |
| mailpit | Catches outgoing mail | `mail.sonora.localhost` (Mailpit UI) |
| traefik | Traefik 3.6, routes `*.sonora.localhost` | Listens on 127.0.0.1, port 80 by default (see `TRAEFIK_PORT`) |
| api | Express app with hot reload | `api.sonora.localhost` through Traefik |
| media-worker | Debian 13 image with ffmpeg 7.1 and libopus. Healthcheck: `ffmpeg -version` | Docker network only |

## Hostnames

Traefik serves these hostnames on port 80 of 127.0.0.1. Set `TRAEFIK_PORT` in `.env` to use another port.

- `api.sonora.localhost`: the API
- `mail.sonora.localhost`: the Mailpit UI
- `s3.sonora.localhost`: the S3 API

## MySQL

- There is one database and one user per module: identity, catalog, media, playback, library, search, recommender, realtime, notification, analytics and platform.
- User names are `<module>_user`, for example `identity_user`.
- The password for every module user comes from `MODULE_DB_PASSWORD` in `.env`.
- The existing `sonora` database and the root user stay in place for Prisma and the tests.
- This setup is for development only. It is not for staging or production.
- `make check-databases` checks that each module user can use only its own database.

## Environment file

- `.env` is gitignored. It holds your local values and must never be committed.
- `.env.example` is committed. It holds placeholders only, never real keys or secrets.

Keys:

| Key | Required | Notes |
| --- | --- | --- |
| `MODULE_DB_PASSWORD` | Yes | Password for the module database users. `make up` fails if it is empty. |
| `TRAEFIK_PORT` | No | Host port for Traefik. Default: 80. |
| `JAMENDO_CLIENT_ID` | No | Needed only to build a real manifest from Jamendo, which is a later step. |

## Seed contract

- Input: `infra/seed/manifest.json`. It lists tracks. Each track has the fields `id`, `title`, `artist`, `licenseCode`, `sourcePageUrl`, `downloadUrl` and `sha256`.
- Output: the tracks are stored in the S3 `originals` bucket.
- Rerun: a rerun is idempotent. It skips any object whose sha256 already exists.
- Checksum: if a download does not match its `sha256`, the seed fails loudly.
- Retries: a 404 or 429 response is retried three times with exponential backoff. After that, the track is recorded as skipped.
- Report: the run writes `seed-report.json` with counts of stored, already present, skipped and failed tracks.
- Test data: the repository ships a small fixture manifest for tests.
- The full 200-track manifest is built from Jamendo. That needs `JAMENDO_CLIENT_ID` and is a later step.

## Note on repositories

Sonora is one repository. The earlier roadmap text about cloning 21 repositories with `clone.sh` does not apply.
