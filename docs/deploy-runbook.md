# Deploy runbook

Status: the repository side is in the repository: the deploy workflows (`.github/workflows/deploy.yml`, `staging.yml`, `production.yml`), the deploy scripts and the forced-command wrapper in `infra/deploy`. The VPS side is not built and is not verified on a VPS. Nothing in this runbook has run on a VPS yet. The VPS, the deploy user, the SSH keys, the GitHub environments and their secrets and variables, the `migrate` compose service, the `web`, `worker` and `realtime` roles, and `/health/ready` do not exist yet. T015.02 to T015.10 build them. Each step below is marked `[not run]` until its check passes on a real VPS.

Blocked until: T005 (domain, DNS and mail) is done, and the VPS and the staging and production secrets exist.

## Environments

| Environment | Trigger | Approval | Target |
| --- | --- | --- | --- |
| staging | successful `ci` run on `main` | none | VPS, staging compose project |
| production | tag `vX.Y.Z` on `main` | owner approval in the GitHub `production` environment | VPS, production compose project |

Production deploys follow the promotion rule: `dev` → `main` is a pull request with `approved: <task id>` from the owner (branching rule M4). Staging gets `main` automatically.

## Hard prerequisites before PRODUCTION_DEPLOY_ENABLED

Do not set `PRODUCTION_DEPLOY_ENABLED` to `true` until both of these are in place. `[not run]`

1. Owner-only tag ruleset: a repository tag ruleset for `v*` that only the owner can create or update. A tag push runs the workflow files from the tagged commit, so this ruleset is what keeps arbitrary tags out of production.
2. Required reviewer: the `production` environment names the owner as a required reviewer, with prevent self-review on.

GitHub environment tag rules are name patterns: they cannot check that a tag is on `main`. The production verify job does that check.

## GitHub environment rules

Repository settings, `[not run]`:

- Environment `staging` restricts deployment branches to `main`.
- Environment `production` restricts deployment tags to `v*`. The owner-only tag ruleset and the verify job described above complete the restriction.

Both workflows call the same reusable job, `.github/workflows/deploy.yml`, with `environment` set to `staging` or `production`. The job runs in that GitHub environment, so it reads only that environment's secrets and variables. Deploys to one environment are queued, never cancelled (`concurrency` group `deploy-<environment>`). `[not run]`

## Repository variables and environment secrets

Create these in repository settings. Names only; no values belong in this file.

- Repository variables (Settings → Secrets and variables → Actions → Variables):
  - `STAGING_DEPLOY_ENABLED`: set to `true` to turn on the staging deploy. `[not run]`
  - `PRODUCTION_DEPLOY_ENABLED`: set to `true` to turn on the production deploy, only after the hard prerequisites above. `[not run]`
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

### Install the scripts as root

The wrapper `infra/deploy/deploy-forced` ships in the repository. Nothing needs to be written. Install it, with the two scripts it uses, from a checkout of the repository on the VPS, as root:

```bash
sudo install -d -o root -g root -m 0755 /srv/sonora/bin
sudo install -o root -g root -m 0755 infra/deploy/deploy-forced infra/deploy/forced-command.sh infra/deploy/deploy.sh /srv/sonora/bin/
```

Run the install again after every change to these scripts. `[not run]`

### Config file /etc/sonora/deploy.env

The wrapper reads its settings from `/etc/sonora/deploy.env`, which is root-owned (root:root, mode 0644). Create the directory and the file as root, then set the owner and mode. The heredoc holds the keys; its values use placeholder hosts only and no secrets:

```bash
sudo install -d -o root -g root -m 0755 /etc/sonora
sudo tee /etc/sonora/deploy.env >/dev/null <<'EOF'
SONORA_ROOT=/srv/sonora
IMAGE_REPO=registry.example.test/sonora
# MODULES is optional. When unset, deploy.sh uses its default module list.
# MODULES=identity catalog media playback library search recommender realtime notification analytics platform
HEALTH_URLS_STAGING=https://staging.example.test/health/ready
HEALTH_URLS_PRODUCTION=https://www.example.test/health/ready
EOF
sudo chown root:root /etc/sonora/deploy.env
sudo chmod 0644 /etc/sonora/deploy.env
```

- `SONORA_ROOT`: the directory that holds `<env>/docker-compose.yml` and `<env>/releases.log`.
- `IMAGE_REPO`: the image repository the `sha-<short>` tags come from.
- `MODULES`: optional, a space-separated module list.
- `HEALTH_URLS_STAGING` and `HEALTH_URLS_PRODUCTION`: space-separated `/health/ready` URLs, one per process role. The wrapper passes the list for its environment to `deploy.sh`.

The wrapper parses this file as data. It reads `KEY=value` lines and never sources or executes it. Values may use only letters, digits and `. _ : / @ , -`, with spaces between list items; a value outside that set is refused. `[not run]`

The wrapper runs the deploy script through `env -i`, so nothing from the caller's environment reaches it. The variables it needs are read from the root-owned config file `/etc/sonora/deploy.env`, not from the caller, so the caller cannot override the gate. `[not run]`

The wrapper also reads a `DEPLOY_CONFIG` path override. That override exists for the tests only. On the VPS it must never be set, which is why sshd must not accept it from a client (see the host settings below).

Host settings on the VPS (`[not run]`):

- sshd: `PermitUserEnvironment no`, and `AcceptEnv` restricted to `LANG` and `LC_*`. With this, a client cannot set `DEPLOY_CONFIG` or any other variable the wrapper would read.
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

## Signals, lock and health gate

- `deploy.sh` ignores SIGHUP and SIGPIPE, so a dropped ssh session does not kill a deploy in progress. `[not run]`
- SIGTERM and SIGINT restore the previous release (no migrations, no log entry) and release the lock. `[not run]`
- The lock is `<env>/.deploy.lock`, a directory holding the owner's pid. A lock whose pid is not a running process is stale and is taken over. A lock with no pid is treated as live while it is younger than 5 seconds, because another deploy may still be between creating it and writing the pid. An older lock with no pid is stale. A takeover moves the stale lock aside under a unique `.deploy.lock.stale.<pid>.<random>` name, removes that copy only if it still holds the stale state that was judged, and otherwise puts it back only when the lock path is free and exits 1 without touching a live owner's lock. `[not run]`
- A first-ever deploy to an environment (no previous release) that is interrupted or fails its health gate has nothing to restore. It stays running and is not logged, so stop it by hand with `docker compose -f /srv/sonora/<env>/docker-compose.yml down`. `[not run]`
- The health gate accepts only HTTP 200. Redirects and 204 are unhealthy. `[not run]`

## Deploy log

- Every `docker compose` call a deploy makes (migrate runs, pull, up -d, the restore after a failed gate, and rollback) appends its stdout and stderr to `$SONORA_ROOT/<env>/deploy.log`. That output never goes to the ssh session, so a dropped ssh session cannot kill docker through a broken pipe. `[not run]`
- `deploy.sh` creates the file with umask 027 (mode 0640), so only the deploy user and its group can read it. `[not run]`
- Nothing in `deploy.sh` rotates or truncates it; set up logrotate for it on the VPS. `[not run]`
- To read it, use `tail -n 200 /srv/sonora/<env>/deploy.log`. When a call fails, `deploy.sh` also prints the last 20 lines to its own stderr. The deploy's progress lines (`deploy: ...`) are not written to this file; `releases.log` remains the release history. `[not run]`

## Deploy order

1. Run migrations first, one `migrate` container per module: `docker compose run --rm migrate`. Abort the deploy if any container exits non-zero. Migrations are expand-only, so the previous release keeps working on the new schema (rule O3). `[not run]`
2. Pull the `sha-<short>` image on the VPS. `[not run]`
3. Run `docker compose up -d` for `api`, `worker`, `media-worker`, `realtime` and `web`. `[not run]`
4. Health gate: poll `/health/ready` on every process role every 5 seconds for 120 seconds, through staging Traefik. Only HTTP 200 passes. A failed gate redeploys the previous tag. `[not run]`

## Staging on a successful ci run on main

1. A successful `ci` run on `main` starts the staging workflow when `STAGING_DEPLOY_ENABLED` is `true`. Its verify job names the image `sha-<first 7 characters of the commit>`. `[not run]`
2. The verify job compares the ci commit with the tip of `main`. If `main` has moved on, it posts a notice and skips the deploy, so an older commit is never deployed over a newer one. `[not run]`
3. Otherwise the deploy job runs over SSH as the deploy user, through the forced command that only runs the deploy script (T015.08). `[not run]`
4. Record the new tag in `/srv/sonora/staging/releases.log`. `[not run]`
5. On a failed gate, the workflow restores the previous image. The expand-only migration stays applied (T015.09). `[not run]`

## Production on tag vX.Y.Z

1. Tag the release `vX.Y.Z` on `main` (`git tag vX.Y.Z` then push the tag). The image for that commit must already exist from the `main` push. The owner-only tag ruleset must be in place first. `[not run]`
2. The verify job checks that the tagged commit is an ancestor of `origin/main`, and fails otherwise. This is the check that keeps a tag off other branches. `[not run]`
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
