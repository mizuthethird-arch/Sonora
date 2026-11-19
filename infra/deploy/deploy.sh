#!/usr/bin/env bash
# Deploys Sonora to one environment and keeps <env>/releases.log as the release history.
# Usage: deploy.sh up <staging|production> <tag>
#        deploy.sh rollback <staging|production>
# Environment: SONORA_ROOT (holds <env>/docker-compose.yml and <env>/releases.log),
# IMAGE_REPO, HEALTH_URLS (space-separated), optional MODULES (space-separated),
# GATE_INTERVAL (default 5) and GATE_TIMEOUT (default 120), both in seconds.
# GATE_TIMEOUT is one deadline shared by all HEALTH_URLS. Only HTTP 200 counts as healthy.
# <env>/.deploy.lock (a directory holding the owner's pid) stops two deploys of one environment
# from running at once; it is removed on exit. A lock with no pid is live for 5 seconds after
# it was created, then stale. HUP is ignored and a closed stderr does not stop a deploy. TERM or
# INT restores the previous release once the new one has started, and starts nothing while
# migrations run.
set -euo pipefail
trap '' HUP PIPE

TAG_RE='^(sha-[0-9a-f]{7,40}|v[0-9]+\.[0-9]+\.[0-9]+)$'
DEFAULT_MODULES="identity catalog media playback library search recommender realtime notification analytics platform"
SERVICES=(api worker media-worker realtime web)
GATE_INTERVAL="${GATE_INTERVAL:-5}"
GATE_TIMEOUT="${GATE_TIMEOUT:-120}"
LOCK_PATH=""
LOCK_HELD=0
# Set by lock_judge: the state of a stale lock (its pid, or pidless-old).
JUDGED=""
HTTP_CODE=000
# Set by deploy_up and rollback so that on_interrupt knows how far the release got.
PHASE="idle"
CUR_ENV=""
PREVIOUS=""
NEW_TAG=""

# Progress is written by an external printf, not the builtin: bash 3.2 buffers a builtin's output
# and flushes it after the stderr redirect is undone, so a failed builtin write to a broken stderr
# lands in stdout and in any later command substitution.

# err MESSAGE: one line on stderr. A failed write (closed or broken stderr) is not an error.
err() {
  /usr/bin/printf '%s\n' "$*" >&2 || true
}

# say MESSAGE: progress line on stderr.
say() {
  err "deploy: $*"
}

# reject MESSAGE: bad arguments; exits 2.
reject() {
  say "$*"
  exit 2
}

# fail MESSAGE: deployment failure; exits 1.
fail() {
  say "$*"
  exit 1
}

usage() {
  err "usage: deploy.sh up <staging|production> <tag>"
  err "       deploy.sh rollback <staging|production>"
  exit 2
}

# valid_env ENV: succeeds only for staging and production.
valid_env() {
  case "$1" in
    staging | production) return 0 ;;
    *) return 1 ;;
  esac
}

# valid_tag TAG: succeeds for sha-<7 to 40 hex> and vMAJOR.MINOR.PATCH.
valid_tag() {
  [[ $1 =~ $TAG_RE ]]
}

# require_config ENV: checks the settings a real run needs and exports IMAGE_REPO.
require_config() {
  local env="$1"
  [ -n "${SONORA_ROOT:-}" ] || fail "SONORA_ROOT is not set"
  [ -n "${IMAGE_REPO:-}" ] || fail "IMAGE_REPO is not set"
  [ -n "${HEALTH_URLS:-}" ] || fail "HEALTH_URLS is not set"
  [ -f "$SONORA_ROOT/$env/docker-compose.yml" ] || fail "missing $SONORA_ROOT/$env/docker-compose.yml"
  export IMAGE_REPO
}

# lock_pid DIR: the pid recorded in lock directory DIR; empty when there is none.
lock_pid() {
  cat "$1/pid" 2>/dev/null || true
}

# lock_age DIR: whole seconds since DIR was last modified. Zero when its time cannot be read.
lock_age() {
  local mtime
  mtime=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || date +%s)
  echo $(($(date +%s) - mtime))
}

# lock_judge DIR: decides whether the lock in DIR is stale. Returns 1 when it is live. Returns 0 when it
# is stale and sets JUDGED to the state it judged: the pid the lock records, or pidless-old. A lock is
# live while the pid it records runs. With no usable pid it is live for 5 seconds after its directory
# was created, because the owner may not have written its pid yet.
lock_judge() {
  local owner
  owner=$(lock_pid "$1")
  case "$owner" in
    '' | *[!0-9]* | 0)
      if [ "$(lock_age "$1")" -lt 5 ]; then
        return 1
      fi
      JUDGED=pidless-old
      ;;
    *)
      if kill -0 "$owner" 2>/dev/null; then
        return 1
      fi
      JUDGED=$owner
      ;;
  esac
  return 0
}

# lock_is_judged DIR STATE: succeeds when DIR still holds the state a judgment recorded: the pid STATE,
# or for pidless-old a lock with no usable pid that is at least 5 seconds old.
lock_is_judged() {
  local owner
  owner=$(lock_pid "$1")
  if [ "$2" = pidless-old ]; then
    case "$owner" in
      '' | *[!0-9]* | 0) [ "$(lock_age "$1")" -ge 5 ] ;;
      *) return 1 ;;
    esac
  else
    [ "$owner" = "$2" ]
  fi
}

# restore_aside ASIDE: puts ASIDE back at LOCK_PATH, only when LOCK_PATH does not exist. mkdir creates
# LOCK_PATH atomically and fails when another deploy holds it, so a directory is never moved into an
# existing one; only the pid file is moved in. If that move fails, the new directory is removed again.
# ASIDE is removed only once it is empty.
restore_aside() {
  local aside="$1"
  mkdir "$LOCK_PATH" 2>/dev/null || return 0
  if [ -e "$aside/pid" ] && ! mv "$aside/pid" "$LOCK_PATH/pid" 2>/dev/null; then
    rmdir "$LOCK_PATH" 2>/dev/null || true
    return 0
  fi
  rmdir "$aside" 2>/dev/null || true
}

# take_over_stale JUDGED: moves the lock aside under a unique name, then checks that the directory moved
# is the state JUDGED recorded. Only then is the stale copy removed. Otherwise another deploy owns the
# lock now: restore_aside puts it back when LOCK_PATH is free, the live owner's lock is never deleted,
# and this returns 1.
take_over_stale() {
  local judged="$1" aside
  aside="$LOCK_PATH.stale.$$.$RANDOM"
  if [ -e "$aside" ]; then
    return 1
  fi
  mv "$LOCK_PATH" "$aside" 2>/dev/null || return 1
  if ! lock_is_judged "$aside" "$judged"; then
    restore_aside "$aside"
    return 1
  fi
  say "taking over stale lock $LOCK_PATH"
  rm -rf "$aside"
}

# release_lock: removes the lock this process holds. Runs on every exit once the lock is taken.
release_lock() {
  if [ "$LOCK_HELD" -eq 1 ]; then
    LOCK_HELD=0
    rm -rf "$LOCK_PATH"
  fi
}

# acquire_lock ENV: takes the environment's deploy lock or exits 1 before any docker call. One stale
# lock is taken over and mkdir retried once; a live owner, or a second lost race, is a failure.
acquire_lock() {
  local env="$1" attempt=1
  LOCK_PATH="$SONORA_ROOT/$env/.deploy.lock"
  until mkdir "$LOCK_PATH" 2>/dev/null; do
    if [ "$attempt" -gt 1 ] || ! lock_judge "$LOCK_PATH"; then
      fail "another deploy is running in $env"
    fi
    attempt=$((attempt + 1))
    take_over_stale "$JUDGED" || fail "another deploy is running in $env"
  done
  LOCK_HELD=1
  trap release_lock EXIT
  printf '%s\n' "$$" >"$LOCK_PATH/pid"
}

# show_log_tail LOG: the last 20 lines of LOG on stderr, so an operator at a terminal sees why a call failed.
# A failed read or write here is not an error.
show_log_tail() {
  local text
  text=$(tail -n 20 "$1" 2>/dev/null) || true
  say "last lines of $1:"
  err "$text"
}

# compose ENV ARGS...: docker compose against the environment's compose file. Its stdout and stderr are
# appended to <env>/deploy.log and never reach the caller's pipes, so a dropped ssh session cannot kill
# docker through a broken pipe. On failure the last lines of that log are shown on stderr.
compose() {
  local env="$1" log rc
  shift
  log="$SONORA_ROOT/$env/deploy.log"
  (umask 027 && : >>"$log") || fail "cannot write $log"
  docker compose -f "$SONORA_ROOT/$env/docker-compose.yml" "$@" >>"$log" 2>&1 && return 0
  rc=$?
  show_log_tail "$log"
  return "$rc"
}

# log_tags ENV: prints the tag of each releases.log line, oldest first.
log_tags() {
  local file="$SONORA_ROOT/$1/releases.log"
  [ -f "$file" ] || return 0
  awk 'NF >= 2 { print $2 }' "$file"
}

# log_count ENV: number of releases in releases.log.
log_count() {
  log_tags "$1" | awk 'END { print NR + 0 }'
}

# nth_last_tag ENV N: the Nth most recent tag (1 is the newest); empty if there are fewer.
nth_last_tag() {
  log_tags "$1" | awk -v n="$2" '{ tags[NR] = $0 } END { if (NR >= n) print tags[NR - n + 1] }'
}

# require_valid_log_tag ENV N: fails before any docker call when the Nth most recent
# releases.log tag is not a valid tag. An empty (missing) entry is allowed.
require_valid_log_tag() {
  local tag
  tag=$(nth_last_tag "$1" "$2")
  if [ -n "$tag" ] && ! valid_tag "$tag"; then
    fail "releases.log for $1 has invalid tag '$tag'"
  fi
}

# record_release ENV TAG: appends the UTC time and tag to releases.log.
record_release() {
  local stamp
  read -r stamp < <(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '%s %s\n' "$stamp" "$2" >>"$SONORA_ROOT/$1/releases.log"
}

# run_migrations ENV: runs each module's migrations in order; stops at the first failure.
run_migrations() {
  local env="$1" module
  local -a modules
  read -r -a modules <<<"${MODULES:-$DEFAULT_MODULES}"
  for module in "${modules[@]}"; do
    say "migrating $module"
    if ! compose "$env" run --rm migrate "$module"; then
      fail "migration for $module failed; nothing was pulled or started"
    fi
  done
}

# start_tag ENV TAG: pulls and starts every service on TAG. Returns 1 on the first failure.
start_tag() {
  local env="$1" tag="$2"
  export SONORA_TAG="$tag"
  compose "$env" pull "${SERVICES[@]}" || return 1
  compose "$env" up -d "${SERVICES[@]}" || return 1
}

# restore_release ENV TAG: brings TAG back without migrations and without a log entry.
# A failed pull is tolerated: up -d still runs and uses the images already present.
restore_release() {
  local env="$1" tag="$2"
  export SONORA_TAG="$tag"
  compose "$env" pull "${SERVICES[@]}" || say "pull of $tag failed, starting from local images"
  compose "$env" up -d "${SERVICES[@]}" || return 1
}

# http_code URL: sets HTTP_CODE to the status curl prints for URL; 000 when the request fails.
http_code() {
  HTTP_CODE=000
  read -r HTTP_CODE < <(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 --max-redirs 0 --url "$1" 2>/dev/null || true) || true
}

# wait_for_url URL INTERVAL DEADLINE: returns 0 once URL answers 200, 1 once SECONDS reaches DEADLINE.
# DEADLINE is an absolute $SECONDS value shared by every URL; each URL gets at least one try.
wait_for_url() {
  local url="$1" interval="$2" deadline="$3"
  http_code "$url"
  while [ "$HTTP_CODE" != 200 ]; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      return 1
    fi
    sleep "$interval"
    http_code "$url"
  done
}

# health_gate: every HEALTH_URLS entry must answer 200 before one shared GATE_TIMEOUT deadline.
health_gate() {
  local url deadline
  local -a urls
  deadline=$((SECONDS + GATE_TIMEOUT))
  read -r -a urls <<<"$HEALTH_URLS"
  for url in "${urls[@]}"; do
    wait_for_url "$url" "$GATE_INTERVAL" "$deadline" || return 1
  done
}

# recover ENV PREVIOUS REASON: puts PREVIOUS back in service after a failed deploy, then exits 1.
recover() {
  local env="$1" previous="$2" reason="$3"
  if [ -z "$previous" ]; then
    fail "$reason, no previous release to restore"
  fi
  PHASE="restoring"
  if ! restore_release "$env" "$previous"; then
    fail "$reason, and restoring $previous also failed"
  fi
  fail "$reason, restored $previous"
}

# deploy_up ENV TAG: migrate, pull and start TAG, gate on health, then log it.
deploy_up() {
  local env="$1" tag="$2"
  require_valid_log_tag "$env" 1
  CUR_ENV="$env"
  NEW_TAG="$tag"
  PREVIOUS=$(nth_last_tag "$env" 1)
  PHASE="migrating"
  run_migrations "$env"
  PHASE="starting"
  start_tag "$env" "$tag" || recover "$env" "$PREVIOUS" "start of $tag failed"
  PHASE="gating"
  health_gate || recover "$env" "$PREVIOUS" "gate failed"
  PHASE="recording"
  record_release "$env" "$tag"
  PHASE="done"
  say "$env now on $tag"
}

# deploy_rollback ENV: redeploys the second-to-last release (no migrations) and logs it.
deploy_rollback() {
  local env="$1"
  if [ "$(log_count "$env")" -lt 2 ]; then
    fail "no previous release to roll back to in $env"
  fi
  require_valid_log_tag "$env" 1
  require_valid_log_tag "$env" 2
  CUR_ENV="$env"
  PREVIOUS=$(nth_last_tag "$env" 1)
  NEW_TAG=$(nth_last_tag "$env" 2)
  PHASE="starting"
  start_tag "$env" "$NEW_TAG" || recover "$env" "$PREVIOUS" "rollback start to $NEW_TAG failed"
  PHASE="gating"
  health_gate || recover "$env" "$PREVIOUS" "rollback gate failed"
  PHASE="recording"
  record_release "$env" "$NEW_TAG"
  PHASE="done"
  say "$env rolled back to $NEW_TAG"
}

# on_interrupt: TERM or INT. Once the new release has started, puts the previous one back; while
# migrations run, starts nothing. Then exits 1, and the EXIT trap releases the lock.
on_interrupt() {
  trap '' INT TERM
  case "$PHASE" in
    starting | gating)
      if [ -z "$PREVIOUS" ]; then
        say "interrupted, no previous release to restore"
      elif restore_release "$CUR_ENV" "$PREVIOUS"; then
        say "interrupted, restored $PREVIOUS"
      else
        say "interrupted, restoring $PREVIOUS also failed"
      fi
      ;;
    restoring) say "interrupted while restoring $PREVIOUS" ;;
    recording) say "interrupted while recording $NEW_TAG, check releases.log" ;;
    done) say "interrupted after $NEW_TAG was recorded" ;;
    *) say "interrupted, nothing started" ;;
  esac
  exit 1
}

main() {
  local action="${1:-}" env="${2:-}"
  case "$action" in
    up)
      [ $# -eq 3 ] || usage
      valid_env "$env" || reject "unknown environment '$env'"
      valid_tag "$3" || reject "invalid tag '$3'"
      require_config "$env"
      acquire_lock "$env"
      deploy_up "$env" "$3"
      ;;
    rollback)
      [ $# -eq 2 ] || usage
      valid_env "$env" || reject "unknown environment '$env'"
      require_config "$env"
      acquire_lock "$env"
      deploy_rollback "$env"
      ;;
    *)
      usage
      ;;
  esac
}

trap on_interrupt INT TERM
main "$@"
