# Deploy runbook

Status: **planned, not built.** The deploy workflows (`.github/workflows/deploy.yml`, `staging.yml`, `production.yml`) and the deploy scripts in `infra/deploy` are in the repository. Nothing in this runbook has run on a VPS yet. The VPS, the deploy user, the SSH keys, the GitHub environments and their secrets and variables, the `migrate` compose service, the `web`, `worker` and `realtime` roles, and `/health/ready` do not exist yet. T015.02 to T015.10 build them. Each step below is marked `[not run]` until its check passes on a real VPS.

Blocked until: T005 (domain, DNS and mail) is done, and the VPS and the staging and production secrets exist.

## Environments

| Environment | Trigger | Approval | Target |
| --- | --- | --- | --- |
| staging | successful `ci` run on `main` | none | VPS, staging compose project |
| production | tag `vX.Y.Z` on `main` | owner approval in the GitHub `production` environment | VPS, production compose project |

Production deploys follow the promotion rule: `dev` → `main` is a pull request with `approved: <task id>` from the owner (branching rule M4). Staging gets `main` automatically.

GitHub environment rules (repository settings, `[not run]`):

- Environment `staging` restricts deployment branches to `main`.
- Environment `production` restricts deployment tags to `v*` on `main`, and requires the owner as a reviewer with prevent self-review. A tag ruleset also restricts who can create `v*` tags. `[not run]`

Both workflows call the same reusable job, `.github/workflows/deploy.yml`, with `environment` set to `staging` or `production`. The job runs in that GitHub environment, so it reads only that environment's secrets and variables. Deploys to one environment are queued, never cancelled (`concurrency` group `deploy-<environment>`). `[not run]`

## Repository variables and environment secrets

Create these in repository settings. Names only; no values belong in this file.

- Repository variables (Settings → Secrets and variables → Actions → Variables):
  - `STAGING_DEPLOY_ENABLED`: set to `true` to turn on the staging deploy. `[not run]`
  - `PRODUCTION_DEPLOY_ENABLED`: set to `true` to turn on the production deploy. `[not run]`
- Environment `staging`:
  - secret `DEPLOY_SSH_KEY`: the staging deploy private key. `[not run]`
  - secret `DEPLOY_KNOWN_HOSTS`: the VPS host public key lines, checked out of band. `[not run]`
  - variable `DEPLOY_HOST`: the staging VPS host name. `[not run]`
  - variable `DEPLOY_USER`: the deploy user on the VPS. `[not run]`
- Environment `production`: the same four names, with the production key and host. Also add the owner as a required reviewer, with prevent self-review. `[not run]`

## Forced command on the VPS

Each environment has its own deploy key, and each key is bound to its environment on the VPS. The deploy user's `authorized_keys` has one line per key (placeholder key, shown without the key material):

```
command="/srv/sonora/bin/deploy-forced staging",restrict ssh-ed25519 AAAA... deploy-staging
command="/srv/sonora/bin/deploy-forced production",restrict ssh-ed25519 AAAA... deploy-production
```

The `restrict` option turns off port forwarding, agent forwarding, the PTY and the other extras. The command argument binds the key to one environment: the key may only run `deploy up` and `deploy rollback` for that environment, and the wrapper refuses any other command or environment. `[not run]`

The wrapper `/srv/sonora/bin/deploy-forced` runs the deploy script through `env -i`, so nothing from the caller's environment reaches it. The variables it needs (SONORA_ROOT, IMAGE_REPO, HEALTH_URLS, MODULES) are read from a root-owned config file, not from the caller, so the caller cannot override the gate. `[not run]`

Host settings on the VPS (`[not run]`):

- sshd: `PermitUserEnvironment no`, and `AcceptEnv` restricted to `LANG` and `LC_*`.
- The scripts under `/srv/sonora/bin` are root-owned scripts, and they are not writable by the deploy user.
- The deploy user is in the `docker` group. Docker access is root-equivalent, so the deploy key is the highest-value credential here: keep one key per environment, and rotate each key on a schedule and whenever a key or the host changes.
- `/srv/sonora/<env>/releases.log` is owned by the deploy user, mode 0640.

T015.08 installs and checks this. `[not run]`

## Scripts and tests

The deploy scripts live in `infra/deploy`. Their tests run locally, with no VPS needed:

```bash
bash infra/deploy/tests/run.sh
```

The VPS side of the scripts is `[not run]` until T015.02 to T015.10 are done.

## Processes deployed

`api`, `worker`, `media-worker`, `realtime` and `web`, all from one image tagged `sha-<short>`, plus the one-off `migrate` container. The image is built once and promoted (rule P3). `[not run]`

## Deploy order

1. Run migrations first, one `migrate` container per module: `docker compose run --rm migrate`. Abort the deploy if any container exits non-zero. Migrations are expand-only, so the previous release keeps working on the new schema (rule O3). `[not run]`
2. Pull the `sha-<short>` image on the VPS. `[not run]`
3. Run `docker compose up -d` for `api`, `worker`, `media-worker`, `realtime` and `web`. `[not run]`
4. Health gate: poll `/health/ready` on every process role every 5 seconds for 120 seconds, through staging Traefik. A failed gate redeploys the previous tag. `[not run]`

## Staging on a successful ci run on main

1. A successful `ci` run on `main` starts the staging workflow when `STAGING_DEPLOY_ENABLED` is `true`. Its verify job names the image `sha-<first 7 characters of the commit>`. `[not run]`
2. The verify job compares the ci commit with the tip of `main`. If `main` has moved on, it posts a notice and skips the deploy, so an older commit is never deployed over a newer one. `[not run]`
3. Otherwise the deploy job runs over SSH as the deploy user, through the forced command that only runs the deploy script (T015.08). `[not run]`
4. Record the new tag in `/srv/sonora/staging/releases.log`. `[not run]`
5. On a failed gate, the workflow restores the previous image. The expand-only migration stays applied (T015.09). `[not run]`

## Production on tag vX.Y.Z

1. Tag the release `vX.Y.Z` on `main` (`git tag vX.Y.Z` then push the tag). The image for that commit must already exist from the `main` push. `[not run]`
2. The verify job checks that the tagged commit is an ancestor of `origin/main`, and fails otherwise. `[not run]`
3. The production workflow waits at the `production` environment for the owner's approval, when `PRODUCTION_DEPLOY_ENABLED` is `true`. `[not run]`
4. Migrations, deploy and health gate run as in staging. The tag deployed is `sha-<first 7 characters of the tagged commit>`. `[not run]`
5. Record the tag in `/srv/sonora/production/releases.log`. `[not run]`

## Rollback

One command per environment:

```bash
deploy rollback staging
deploy rollback production
```

It reads the previous tag from `/srv/sonora/<env>/releases.log` and redeploys that tag's image. `deploy rollback` toggles between the last two releases: the first rollback returns to the previous release, and a second rollback returns to the first one. It does not roll back migrations, because they are expand-only (rule O2). `[not run]`

Timing is measured when T015.10 runs. The target is under 2 minutes.

| Environment | Command | Target | Measured time |
| --- | --- | --- | --- |
| staging | `deploy rollback staging` | under 2 minutes | [not timed] |
| production | `deploy rollback production` | under 2 minutes | [not timed] |

## Checks

- Staging smoke test: `/health/ready` of every process role through staging Traefik returns 200 within 90 seconds (T015.02). `[not run]`
- Failed-gate test: the previous image is restored and the old version still works on the migrated schema (T015.09). `[not run]`
- Broken staging release auto-rolls back, and a manual production rollback finishes under 2 minutes (T015.10). `[not run]`

## Secrets

Each environment has its own deploy SSH key, stored as a GitHub environment secret (`DEPLOY_SSH_KEY`). The key is restricted on the VPS with an `authorized_keys` forced command (see above, T015.08). The deploy workflow writes the key and `known_hosts` to the runner's temporary directory with restricted permissions, passes them only through environment variables, and deletes them when the job ends, even on failure. No secret is written to logs or to this file.
