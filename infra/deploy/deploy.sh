#!/usr/bin/env bash
# Deploys Sonora to one environment and keeps <env>/releases.log as the release history.
# Usage: deploy.sh up <staging|production> <tag>
#        deploy.sh rollback <staging|production>
# Environment: SONORA_ROOT (holds <env>/docker-compose.yml and <env>/releases.log),
# IMAGE_REPO, HEALTH_URLS (space-separated), optional MODULES (space-separated),
# GATE_INTERVAL (default 5) and GATE_TIMEOUT (default 120), both in seconds.
set -euo pipefail

TAG_RE='^(sha-[0-9a-f]{7,40}|v[0-9]+\.[0-9]+\.[0-9]+)$'
DEFAULT_MODULES="identity catalog media playback library search recommender realtime notification analytics platform"
SERVICES=(api worker media-worker realtime web)
GATE_INTERVAL="${GATE_INTERVAL:-5}"
GATE_TIMEOUT="${GATE_TIMEOUT:-120}"

# say MESSAGE: progress line on stderr.
say() {
  echo "deploy: $*" >&2
}

# reject MESSAGE: bad arguments; exits 2.
reject() {
  echo "deploy: $*" >&2
  exit 2
}

# fail MESSAGE: deployment failure; exits 1.
fail() {
  echo "deploy: $*" >&2
  exit 1
}

usage() {
  echo "usage: deploy.sh up <staging|production> <tag>" >&2
  echo "       deploy.sh rollback <staging|production>" >&2
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

compose_file() {
  printf '%s/%s/docker-compose.yml' "$SONORA_ROOT" "$1"
}

log_file() {
  printf '%s/%s/releases.log' "$SONORA_ROOT" "$1"
}

# require_config ENV: checks the settings a real run needs and exports IMAGE_REPO.
require_config() {
  local env="$1"
  [ -n "${SONORA_ROOT:-}" ] || fail "SONORA_ROOT is not set"
  [ -n "${IMAGE_REPO:-}" ] || fail "IMAGE_REPO is not set"
  [ -n "${HEALTH_URLS:-}" ] || fail "HEALTH_URLS is not set"
  [ -f "$(compose_file "$env")" ] || fail "missing $(compose_file "$env")"
  export IMAGE_REPO
}

# compose ENV ARGS...: docker compose against the environment's compose file.
compose() {
  local env="$1"
  shift
  docker compose -f "$(compose_file "$env")" "$@"
}

# log_tags ENV: prints the tag of each releases.log line, oldest first.
log_tags() {
  local file
  file=$(log_file "$1")
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

# record_release ENV TAG: appends the UTC time and tag to releases.log.
record_release() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$2" >>"$(log_file "$1")"
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
restore_release() {
  local env="$1" tag="$2"
  export SONORA_TAG="$tag"
  compose "$env" up -d "${SERVICES[@]}" || return 1
}

# wait_for_url URL INTERVAL TIMEOUT: returns 0 once URL answers, 1 after TIMEOUT seconds.
wait_for_url() {
  local url="$1" interval="$2" timeout="$3" deadline
  deadline=$((SECONDS + timeout))
  while ! curl -fsS -o /dev/null --max-time 10 "$url"; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      return 1
    fi
    sleep "$interval"
  done
}

# health_gate: every HEALTH_URLS entry must answer within GATE_TIMEOUT.
health_gate() {
  local url
  local -a urls
  read -r -a urls <<<"$HEALTH_URLS"
  for url in "${urls[@]}"; do
    wait_for_url "$url" "$GATE_INTERVAL" "$GATE_TIMEOUT" || return 1
  done
}

# recover ENV PREVIOUS REASON: puts PREVIOUS back in service after a failed deploy, then exits 1.
recover() {
  local env="$1" previous="$2" reason="$3"
  if [ -z "$previous" ]; then
    fail "$reason, no previous release to restore"
  fi
  if ! restore_release "$env" "$previous"; then
    fail "$reason, and restoring $previous also failed"
  fi
  fail "$reason, restored $previous"
}

# deploy_up ENV TAG: migrate, pull and start TAG, gate on health, then log it.
deploy_up() {
  local env="$1" tag="$2" previous
  previous=$(nth_last_tag "$env" 1)
  export SONORA_TAG="$tag"
  run_migrations "$env"
  start_tag "$env" "$tag" || recover "$env" "$previous" "start of $tag failed"
  health_gate || recover "$env" "$previous" "gate failed"
  record_release "$env" "$tag"
  say "$env now on $tag"
}

# deploy_rollback ENV: redeploys the second-to-last release (no migrations) and logs it.
deploy_rollback() {
  local env="$1" current target
  if [ "$(log_count "$env")" -lt 2 ]; then
    fail "no previous release to roll back to in $env"
  fi
  current=$(nth_last_tag "$env" 1)
  target=$(nth_last_tag "$env" 2)
  start_tag "$env" "$target" || recover "$env" "$current" "rollback start to $target failed"
  health_gate || recover "$env" "$current" "rollback gate failed"
  record_release "$env" "$target"
  say "$env rolled back to $target"
}

main() {
  local action="${1:-}" env="${2:-}"
  case "$action" in
    up)
      [ $# -eq 3 ] || usage
      valid_env "$env" || reject "unknown environment '$env'"
      valid_tag "$3" || reject "invalid tag '$3'"
      require_config "$env"
      deploy_up "$env" "$3"
      ;;
    rollback)
      [ $# -eq 2 ] || usage
      valid_env "$env" || reject "unknown environment '$env'"
      require_config "$env"
      deploy_rollback "$env"
      ;;
    *)
      usage
      ;;
  esac
}

main "$@"
