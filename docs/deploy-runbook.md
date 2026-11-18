# Deploy runbook

Status: **planned, not built.** Nothing in this runbook has run yet. The VPS, the deploy user, the SSH key, the GitHub environments, the `migrate` compose service, the `web`, `worker` and `realtime` roles, and `/health/ready` do not exist yet. T015.02 to T015.10 build them. Each step below is marked `[not run]` until its check passes.

Blocked until: T005 (domain, DNS and mail) is done, and the VPS and the staging and production secrets exist.

## Environments

| Environment | Trigger | Approval | Target |
| --- | --- | --- | --- |
| staging | merge to `main` | none | VPS, staging compose project |
| production | tag `vX.Y.Z` | owner approval in the GitHub `production` environment | VPS, production compose project |

Production deploys follow the promotion rule: `dev` → `main` is a pull request with `approved: <task id>` from the owner (branching rule M4). Staging gets `main` automatically.

## Processes deployed

`api`, `worker`, `media-worker`, `realtime` and `web`, all from one image tagged `sha-<short>`, plus the one-off `migrate` container. The image is built once and promoted (rule P3). `[not run]`

## Deploy order

1. Run migrations first, one `migrate` container per module: `docker compose run --rm migrate`. Abort the deploy if any container exits non-zero. Migrations are expand-only, so the previous release keeps working on the new schema (rule O3). `[not run]`
2. Pull the `sha-<short>` image on the VPS.
3. Run `docker compose up -d` for `api`, `worker`, `media-worker`, `realtime` and `web`. `[not run]`
4. Health gate: poll `/health/ready` on every process role every 5 seconds for 120 seconds, through staging Traefik. A failed gate redeploys the previous tag. `[not run]`

## Staging on merge to main

1. Merge to `main` starts the deploy workflow over SSH as the deploy user, through a forced command that only runs the deploy script (T015.08). `[not run]`
2. Record the new tag in `/srv/sonora/staging/releases.log`. `[not run]`
3. On a failed gate, the workflow restores the previous image. The expand-only migration stays applied (T015.09). `[not run]`

## Production on tag vX.Y.Z

1. Tag the release `vX.Y.Z` on `main` (`git tag vX.Y.Z` then push the tag). `[not run]`
2. The production workflow waits at the `production` environment for the owner's approval. `[not run]`
3. Migrations, deploy and health gate run as in staging. `[not run]`
4. Record the tag in `/srv/sonora/production/releases.log`. `[not run]`

## Rollback

One command per environment:

```bash
deploy rollback staging
deploy rollback production
```

It reads the previous tag from `/srv/sonora/<env>/releases.log` and redeploys that tag's image. It does not roll back migrations, because they are expand-only (rule O2). `[not run]`

Target: under 2 minutes. Timing is recorded in this section when T015.10 runs. `[not timed]`

## Checks

- Staging smoke test: `/health/ready` of every process role through staging Traefik returns 200 within 90 seconds (T015.02). `[not run]`
- Failed-gate test: the previous image is restored and the old version still works on the migrated schema (T015.09). `[not run]`
- Broken staging release auto-rolls back, and a manual production rollback finishes under 2 minutes (T015.10). `[not run]`

## Secrets

Each environment has its own deploy SSH key, stored as a GitHub environment secret. The key is restricted on the VPS with an `authorized_keys` forced command (T015.08). No secret is written to logs or to this file.
