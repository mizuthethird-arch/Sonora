#!/usr/bin/env bash
# Tests for infra/deploy/deploy.sh, smoke.sh, forced-command.sh and deploy-forced.
# Each case runs in its own temp dir with fake docker and curl first on PATH,
# so no container, registry or host is touched. Prints PASS or FAIL per case.
# Bash 3.2 compatible (macOS /bin/bash). Runner has no -e: cases use && chains.
set -uo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
deploy_dir=$(cd "$tests_dir/.." && pwd)
failures=0
expected_modules="identity catalog media playback library search recommender realtime notification analytics platform"
services="api worker media-worker realtime web"
MIGRATE='docker compose -f [^ ]+ run --rm migrate '
PULL='docker compose -f [^ ]+ pull '
UP='docker compose -f [^ ]+ up -d '

write_fakes() {
  mkdir -p "$W/fc" "$W/fdf"
  cat >"$W/bin/docker" <<'EOF'
#!/usr/bin/env bash
# Fake docker. Records every call with the SONORA_TAG and IMAGE_REPO it ran with.
# FAKE_MIGRATE_FAIL=all fails every migrate run; any other value fails only that module.
# FAKE_MIGRATE_SLEEP=N makes every migrate run take N seconds (after it is recorded).
printf 'SONORA_TAG=%s IMAGE_REPO=%s docker %s\n' "${SONORA_TAG:-}" "${IMAGE_REPO:-}" "$*" >>"$FAKE_CALLS"
# With FAKE_LOCK_DIR set, records whether that lock directory exists at each docker call.
if [ -n "${FAKE_LOCK_DIR:-}" ]; then
  if [ -d "$FAKE_LOCK_DIR" ]; then echo yes >>"$FAKE_STATE/lock_seen"; else echo no >>"$FAKE_STATE/lock_seen"; fi
fi
if [ -n "${SONORA_TAG:-}" ]; then
  printf '%s\n' "$SONORA_TAG" >"$FAKE_STATE/last_tag"
fi
case " $* " in
  *" run "*)
    module=""
    for arg in "$@"; do module=$arg; done
    if [ -n "${FAKE_MIGRATE_SLEEP:-}" ]; then sleep "$FAKE_MIGRATE_SLEEP"; fi
    if [ -n "${FAKE_MIGRATE_FAIL:-}" ] && { [ "$FAKE_MIGRATE_FAIL" = all ] || [ "$FAKE_MIGRATE_FAIL" = "$module" ]; }; then
      echo "fake docker: migrate $module failed" >&2
      exit 1
    fi
    ;;
esac
exit 0
EOF
  cat >"$W/bin/curl" <<'EOF'
#!/usr/bin/env bash
# Fake curl. Prints the code as curl -w '%{http_code}' does. Failing (FAKE_CURL_FAIL=1, or the last
# SONORA_TAG docker ran with equals FAKE_CURL_FAIL_AFTER_TAG) prints 000 and exits 7. Otherwise it
# prints FAKE_CURL_CODE (default 200) and exits 0, as curl does without -f.
printf 'curl %s\n' "$*" >>"$FAKE_CALLS"
if [ "${FAKE_CURL_FAIL:-0}" = 1 ]; then
  printf '000'
  exit 7
fi
if [ -n "${FAKE_CURL_FAIL_AFTER_TAG:-}" ] && [ -f "$FAKE_STATE/last_tag" ] &&
  [ "$(cat "$FAKE_STATE/last_tag")" = "$FAKE_CURL_FAIL_AFTER_TAG" ]; then
  printf '000'
  exit 7
fi
printf '%s' "${FAKE_CURL_CODE:-200}"
exit 0
EOF
  cat >"$W/fc/deploy.sh" <<'EOF'
#!/usr/bin/env bash
# Stands in for deploy.sh next to the copied forced-command.sh: records the arguments it was given.
printf '%s\n' "$*" >"$FAKE_STATE/deploy-args"
EOF
  cat >"$W/fdf/forced-command.sh" <<'EOF'
#!/usr/bin/env bash
# Stands in for forced-command.sh next to a copied deploy-forced: dumps its environment and argv
# into the working directory, which the test sets.
env >dump-env.txt
printf '%s\n' "$@" >dump-argv.txt
EOF
  cat >"$W/bin/mv" <<'EOF'
#!/usr/bin/env bash
# Fake mv. With FAKE_MV_RACE set to a lock directory, the first mv that moves that directory first
# rewrites its pid file to FAKE_RACE_PID, as if another deploy had taken the lock in between.
if [ -n "${FAKE_MV_RACE:-}" ]; then
  src=""
  for arg in "$@"; do
    case "$arg" in
      -*) ;;
      *)
        src=$arg
        break
        ;;
    esac
  done
  if [ "$src" = "$FAKE_MV_RACE" ] && [ -d "$src" ]; then
    printf '%s\n' "$FAKE_RACE_PID" >"$src/pid"
  fi
fi
exec /bin/mv "$@"
EOF
  chmod +x "$W/bin/docker" "$W/bin/curl" "$W/bin/mv" "$W/fc/deploy.sh" "$W/fdf/forced-command.sh"
}

setup_sandbox() {
  mkdir -p "$W/bin" "$W/root/staging" "$W/root/production"
  : >"$W/calls"
  : >"$W/root/staging/docker-compose.yml"
  : >"$W/root/production/docker-compose.yml"
  write_fakes
  export PATH="$W/bin:$PATH" FAKE_CALLS="$W/calls" FAKE_STATE="$W"
  export SONORA_ROOT="$W/root" IMAGE_REPO="registry.example.test/sonora"
  export GATE_INTERVAL=1 GATE_TIMEOUT=3 SMOKE_INTERVAL=1 SMOKE_TIMEOUT=3
  export HEALTH_URLS="http://127.0.0.1:9/health/ready"
  export SMOKE_URLS="http://127.0.0.1:9/a http://127.0.0.1:9/b"
  unset DEPLOY_SCRIPT DEPLOY_CONFIG
  unset MODULES SONORA_TAG SSH_ORIGINAL_COMMAND FAKE_MIGRATE_FAIL FAKE_CURL_FAIL FAKE_CURL_FAIL_AFTER_TAG
  unset FAKE_LOCK_DIR FAKE_CURL_CODE FAKE_MIGRATE_SLEEP FAKE_MV_RACE FAKE_RACE_PID
  RC=0
}

# run_script NAME ARGS...: runs infra/deploy/NAME with bash. Sets RC, stdout to $W/out, stderr to $W/err.
# Returns 1 when the script is missing, so the case fails instead of crashing.
run_script() {
  local name="$1"
  shift
  RC=0
  if [ ! -f "$deploy_dir/$name" ]; then
    echo "    missing script: infra/deploy/$name" >&2
    return 1
  fi
  bash "$deploy_dir/$name" "$@" >"$W/out" 2>"$W/err" </dev/null || RC=$?
}

expect() {
  local message="$1"
  shift
  if "$@"; then
    return 0
  fi
  echo "    not ok: $message" >&2
  return 1
}

expect_rc() { expect "exit status $1, got $RC" [ "$RC" -eq "$1" ]; }
expect_err() { expect "stderr mentions: $1" grep -Fq -- "$1" "$W/err"; }
expect_named() { expect "output names: $1" grep -Fq -- "$1" "$W/out" "$W/err"; }

log_file() { printf '%s/%s/releases.log' "$SONORA_ROOT" "$1"; }

lock_dir() { printf '%s/%s/.deploy.lock' "$SONORA_ROOT" "$1"; }

# lock_held_during_deploy: every docker call of the case ran while the lock directory existed.
lock_held_during_deploy() { [ -s "$W/lock_seen" ] && ! grep -q no "$W/lock_seen"; }

# curl_calls_are_hardened: every curl call passes --max-redirs 0 and takes its url after --url.
curl_calls_are_hardened() {
  local total
  total=$(calls_count '^curl ')
  [ "$total" -ge 1 ] || return 1
  [ "$(grep -E '^curl ' "$FAKE_CALLS" | grep -c -- '--max-redirs 0')" -eq "$total" ] || return 1
  [ "$(grep -E '^curl ' "$FAKE_CALLS" | grep -Ec -- '--url https?://[^ ]+( |$)')" -eq "$total" ]
}

seed_log() {
  local env="$1" tag
  shift
  : >"$(log_file "$env")"
  for tag in "$@"; do
    printf '2026-11-01T10:00:00Z %s\n' "$tag" >>"$(log_file "$env")"
  done
}

snapshot_log() {
  cat "$(log_file "$1")" 2>/dev/null >"$W/log.before"
  return 0
}

log_unchanged() {
  [ "$(cat "$(log_file "$1")" 2>/dev/null)" = "$(cat "$W/log.before")" ]
}

log_lines() { cat "$(log_file "$1")" 2>/dev/null | wc -l | tr -d ' '; }

last_log_entry_is() {
  tail -n 1 "$(log_file "$1")" 2>/dev/null | grep -Eq "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[^[:space:]]+ $2\$"
}

calls_count() { grep -cE -- "$1" "$FAKE_CALLS" || true; }
first_call_line() { grep -nE -- "$1" "$FAKE_CALLS" | head -n 1 | cut -d: -f1; }
last_call_line() { grep -nE -- "$1" "$FAKE_CALLS" | tail -n 1 | cut -d: -f1; }
tags_of() { grep -E -- "$1" "$FAKE_CALLS" | sed -E 's/^SONORA_TAG=([^ ]*) .*/\1/'; }
migrate_modules() { grep -E -- "$MIGRATE" "$FAKE_CALLS" | awk '{ print $NF }' | paste -sd ' ' -; }

# call_names_all_services PATTERN: the first matching call names every service.
call_names_all_services() {
  local line svc
  line=$(grep -E -- "$1" "$FAKE_CALLS" | head -n 1)
  [ -n "$line" ] || return 1
  for svc in $services; do
    case " $line " in
      *" $svc "*) ;;
      *) return 1 ;;
    esac
  done
}

migrations_before_pull_and_up() {
  local migrate pull up
  migrate=$(last_call_line "$MIGRATE")
  pull=$(first_call_line "$PULL")
  up=$(first_call_line "$UP")
  [ -n "$migrate" ] && [ -n "$pull" ] && [ -n "$up" ] &&
    [ "$migrate" -lt "$pull" ] && [ "$pull" -lt "$up" ]
}

case_smoke_ok() {
  run_script smoke.sh && expect_rc 0 &&
    expect "polls both SMOKE_URLS" [ "$(calls_count '^curl ')" -ge 2 ] &&
    run_script smoke.sh http://127.0.0.1:9/c && expect_rc 0
}

case_smoke_timeout() {
  export FAKE_CURL_FAIL=1 &&
    run_script smoke.sh && expect_rc 1 &&
    expect_named 'http://127.0.0.1:9/a' &&
    expect_named 'http://127.0.0.1:9/b'
}

case_up_success() {
  seed_log staging sha-1111111 &&
    run_script deploy.sh up staging sha-abcdef1 && expect_rc 0 &&
    expect "migrations run for each module in MODULES order" [ "$(migrate_modules)" = "$expected_modules" ] &&
    expect "all migrations run before the pull and the up" migrations_before_pull_and_up &&
    expect "pull names api worker media-worker realtime web" call_names_all_services "$PULL" &&
    expect "up -d names the same five services" call_names_all_services "$UP" &&
    expect "pull runs with SONORA_TAG=sha-abcdef1" [ "$(tags_of "$PULL" | tail -n 1)" = sha-abcdef1 ] &&
    expect "up -d runs with SONORA_TAG=sha-abcdef1" [ "$(tags_of "$UP" | tail -n 1)" = sha-abcdef1 ] &&
    expect "IMAGE_REPO is passed to docker" grep -Fq 'IMAGE_REPO=registry.example.test/sonora' "$FAKE_CALLS" &&
    expect "the health gate polls HEALTH_URLS" [ "$(calls_count '^curl ')" -ge 1 ] &&
    expect "releases.log keeps the old line and gains one" [ "$(log_lines staging)" -eq 2 ] &&
    expect "releases.log last line records sha-abcdef1" last_log_entry_is staging sha-abcdef1
}

case_migration_failure_aborts() {
  seed_log staging sha-1111111 && snapshot_log staging &&
    export FAKE_MIGRATE_FAIL=catalog &&
    run_script deploy.sh up staging sha-abcdef1 &&
    expect "exit status non-zero, got $RC" [ "$RC" -ne 0 ] &&
    expect "migrations stop at the failing module" [ "$(migrate_modules)" = "identity catalog" ] &&
    expect "no pull runs" [ "$(calls_count "$PULL")" -eq 0 ] &&
    expect "no up -d runs" [ "$(calls_count "$UP")" -eq 0 ] &&
    expect "releases.log is unchanged" log_unchanged staging
}

case_gate_failure_restores_previous() {
  seed_log staging sha-1111111 && snapshot_log staging &&
    export FAKE_CURL_FAIL_AFTER_TAG=sha-2222222 &&
    run_script deploy.sh up staging sha-2222222 && expect_rc 1 &&
    expect_err 'gate failed, restored sha-1111111' &&
    expect "two up -d runs: the new tag, then the previous tag" [ "$(tags_of "$UP" | paste -sd ' ' -)" = "sha-2222222 sha-1111111" ] &&
    expect "migrations ran once, not again on restore" [ "$(calls_count "$MIGRATE")" -eq 11 ] &&
    expect "no down or revert call (expand-only migration stays applied)" [ "$(calls_count '(^| )down( |$)|revert')" -eq 0 ] &&
    expect "releases.log is unchanged" log_unchanged staging
}

case_gate_failure_without_previous() {
  snapshot_log staging &&
    export FAKE_CURL_FAIL=1 &&
    run_script deploy.sh up staging sha-2222222 && expect_rc 1 &&
    expect_err 'gate failed, no previous release' &&
    expect "only the new up -d ran, no restore" [ "$(calls_count "$UP")" -eq 1 ] &&
    expect "releases.log has no entry" [ ! -s "$(log_file staging)" ] &&
    expect "releases.log is unchanged" log_unchanged staging
}

case_rollback_uses_second_to_last() {
  seed_log staging sha-aaaaaaa sha-bbbbbbb sha-ccccccc &&
    run_script deploy.sh rollback staging && expect_rc 0 &&
    expect "rollback runs no migrations" [ "$(calls_count "$MIGRATE")" -eq 0 ] &&
    expect "pull runs with sha-bbbbbbb, the second-to-last tag" [ "$(tags_of "$PULL" | tail -n 1)" = sha-bbbbbbb ] &&
    expect "up -d runs with sha-bbbbbbb" [ "$(tags_of "$UP" | tail -n 1)" = sha-bbbbbbb ] &&
    expect "pull names the five services" call_names_all_services "$PULL" &&
    expect "up -d names the five services" call_names_all_services "$UP" &&
    expect "releases.log gained sha-bbbbbbb" last_log_entry_is staging sha-bbbbbbb &&
    expect "releases.log has four lines" [ "$(log_lines staging)" -eq 4 ]
}

case_rollback_with_one_line_fails() {
  seed_log staging sha-aaaaaaa && snapshot_log staging &&
    run_script deploy.sh rollback staging && expect_rc 1 &&
    expect_err 'no previous release' &&
    expect "rollback runs no pull or up" [ "$(calls_count 'pull |up -d ')" -eq 0 ] &&
    expect "releases.log is unchanged" log_unchanged staging
}

case_rejects_bad_tag_and_env() {
  local tag env
  for tag in latest sha-abc sha-ABCDEF1 sha-abcdef1x v1.2 v1.2.3.4 1.2.3 'sha-abcdef1;id' '../sha-abcdef1' ''; do
    : >"$FAKE_CALLS"
    run_script deploy.sh up staging "$tag" || return 1
    expect "bad tag '$tag' exits 2 (got $RC)" [ "$RC" -eq 2 ] || return 1
    expect "bad tag '$tag' runs no docker" [ ! -s "$FAKE_CALLS" ] || return 1
  done
  for env in qa prod Staging production-eu ''; do
    : >"$FAKE_CALLS"
    run_script deploy.sh up "$env" sha-abcdef1 || return 1
    expect "unknown env '$env' exits non-zero (got $RC)" [ "$RC" -ne 0 ] || return 1
    expect "unknown env '$env' runs no docker" [ ! -s "$FAKE_CALLS" ] || return 1
  done
}

case_forced_command_accepts_allowed_forms() {
  local cmd key_env
  for cmd in 'deploy up staging sha-abcdef1' 'deploy up production v1.2.3' \
    'deploy rollback staging' 'deploy rollback production'; do
    key_env=$(printf '%s\n' "$cmd" | cut -d' ' -f3)
    rm -f "$W/deploy-args"
    export SSH_ORIGINAL_COMMAND="$cmd"
    run_forced_command "$key_env" || return 1
    expect "'$cmd' runs the deploy script (exit $RC)" [ "$RC" -eq 0 ] || return 1
    expect "'$cmd' passes its arguments without the word deploy" \
      [ "$(cat "$W/deploy-args" 2>/dev/null)" = "${cmd#deploy }" ] || return 1
  done
}

case_forced_command_rejects_hostile_commands() {
  local cmd
  local -a hostile
  hostile=(
    ''
    'ls'
    'deploy'
    'deploy up staging'
    'deploy up staging sha-abcdef1 extra'
    'deploy up staging sha-abcdef1; id'
    'deploy up staging sha-abcdef1 && id'
    'deploy up staging $(id)'
    'deploy up staging `id`'
    $'deploy up staging sha-abcdef1\nid'
    'deploy up qa sha-abcdef1'
    'deploy up staging latest'
    'deploy up staging v1.2'
    'deploy rollback staging extra'
    'deploy rollback'
    'deploy down staging'
    'deploy rollback staging; id'
    'deploy rollback production | sh'
    'DEPLOY rollback staging'
  )
  for cmd in "${hostile[@]}"; do
    rm -f "$W/deploy-args"
    export SSH_ORIGINAL_COMMAND="$cmd"
    run_forced_command staging || return 1
    expect "rejects [$cmd] with exit 126 (got $RC)" [ "$RC" -eq 126 ] || return 1
    expect "rejects [$cmd] with 'rejected' on stderr" grep -qi rejected "$W/err" || return 1
    expect "rejects [$cmd] and runs nothing" [ ! -e "$W/deploy-args" ] || return 1
  done
}

case_forced_command_staging_key_rejects_production() {
  local cmd
  for cmd in 'deploy up production sha-abcdef1' 'deploy rollback production'; do
    rm -f "$W/deploy-args"
    export SSH_ORIGINAL_COMMAND="$cmd"
    run_forced_command staging || return 1
    expect "staging key rejects [$cmd] with exit 126 (got $RC)" [ "$RC" -eq 126 ] || return 1
    expect "staging key rejects [$cmd] with 'rejected' on stderr" grep -qi rejected "$W/err" || return 1
    expect "staging key rejects [$cmd] and runs nothing" [ ! -e "$W/deploy-args" ] || return 1
  done
}

case_forced_command_production_key_rejects_staging() {
  local cmd
  for cmd in 'deploy up staging sha-abcdef1' 'deploy rollback staging'; do
    rm -f "$W/deploy-args"
    export SSH_ORIGINAL_COMMAND="$cmd"
    run_forced_command production || return 1
    expect "production key rejects [$cmd] with exit 126 (got $RC)" [ "$RC" -eq 126 ] || return 1
    expect "production key rejects [$cmd] with 'rejected' on stderr" grep -qi rejected "$W/err" || return 1
    expect "production key rejects [$cmd] and runs nothing" [ ! -e "$W/deploy-args" ] || return 1
  done
}

case_forced_command_needs_valid_env_argument() {
  local arg
  export SSH_ORIGINAL_COMMAND='deploy rollback staging'
  rm -f "$W/deploy-args"
  run_forced_command || return 1
  expect "no argument exits 126 (got $RC)" [ "$RC" -eq 126 ] || return 1
  expect "no argument prints 'rejected' on stderr" grep -qi rejected "$W/err" || return 1
  expect "no argument runs nothing" [ ! -e "$W/deploy-args" ] || return 1
  for arg in '' qa Staging 'staging production' 'staging;id'; do
    rm -f "$W/deploy-args"
    run_forced_command "$arg" || return 1
    expect "argument [$arg] exits 126 (got $RC)" [ "$RC" -eq 126 ] || return 1
    expect "argument [$arg] prints 'rejected' on stderr" grep -qi rejected "$W/err" || return 1
    expect "argument [$arg] runs nothing" [ ! -e "$W/deploy-args" ] || return 1
  done
}

case_forced_command_production_key_accepts_production() {
  local cmd
  for cmd in 'deploy up production v1.2.3' 'deploy rollback production'; do
    rm -f "$W/deploy-args"
    export SSH_ORIGINAL_COMMAND="$cmd"
    run_forced_command production || return 1
    expect "production key runs [$cmd] (exit $RC)" [ "$RC" -eq 0 ] || return 1
    expect "production key passes [$cmd] without the word deploy" \
      [ "$(cat "$W/deploy-args" 2>/dev/null)" = "${cmd#deploy }" ] || return 1
  done
}

case_lock_held_by_live_pid_blocks_deploy() {
  local pid
  seed_log staging sha-1111111
  sleep 30 &
  pid=$!
  mkdir "$(lock_dir staging)" && printf '%s\n' "$pid" >"$(lock_dir staging)/pid"
  run_script deploy.sh up staging sha-abcdef1
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  expect_rc 1 &&
    expect_err 'another deploy is running' &&
    expect "no docker call while the lock is held" [ ! -s "$FAKE_CALLS" ] &&
    expect "the live owner's lock is left in place" [ -f "$(lock_dir staging)/pid" ] &&
    expect "releases.log is unchanged" last_log_entry_is staging sha-1111111
}

case_lock_with_dead_pid_is_taken_over() {
  local pid
  seed_log staging sha-1111111
  sleep 0 &
  pid=$!
  wait "$pid"
  mkdir "$(lock_dir staging)" && printf '%s\n' "$pid" >"$(lock_dir staging)/pid"
  export FAKE_LOCK_DIR="$(lock_dir staging)"
  run_script deploy.sh up staging sha-abcdef1 && expect_rc 0 &&
    expect "the deploy ran and took the stale lock" [ "$(calls_count "$MIGRATE")" -ge 1 ] &&
    expect "the lock was held during the docker calls" lock_held_during_deploy &&
    expect "the stale lock is gone afterwards" [ ! -e "$(lock_dir staging)" ]
}

case_lock_released_after_success() {
  seed_log staging sha-1111111
  export FAKE_LOCK_DIR="$(lock_dir staging)"
  run_script deploy.sh up staging sha-abcdef1 && expect_rc 0 &&
    expect "the lock was held during the docker calls" lock_held_during_deploy &&
    expect "the lock is removed on success" [ ! -e "$(lock_dir staging)" ]
}

case_lock_released_after_failure() {
  seed_log staging sha-1111111
  export FAKE_LOCK_DIR="$(lock_dir staging)" FAKE_MIGRATE_FAIL=all
  run_script deploy.sh up staging sha-abcdef1 && expect_rc 1 &&
    expect "the lock was held during the docker calls" lock_held_during_deploy &&
    expect "the lock is removed on failure" [ ! -e "$(lock_dir staging)" ]
}

case_up_rejects_invalid_previous_tag() {
  seed_log staging sha-1111111 'bad;tag' && snapshot_log staging &&
    run_script deploy.sh up staging sha-abcdef1 && expect_rc 1 &&
    expect_err 'releases.log' &&
    expect "no docker call for a bad previous tag" [ ! -s "$FAKE_CALLS" ] &&
    expect "releases.log is unchanged" log_unchanged staging
}

case_rollback_rejects_invalid_tags() {
  seed_log staging sha-aaaaaaa 'bad;tag' sha-ccccccc && snapshot_log staging &&
    run_script deploy.sh rollback staging && expect_rc 1 &&
    expect_err 'releases.log' &&
    expect "bad second-to-last tag: no docker call" [ ! -s "$FAKE_CALLS" ] &&
    expect "bad second-to-last tag: releases.log unchanged" log_unchanged staging || return 1
  seed_log staging sha-aaaaaaa sha-bbbbbbb 'bad;tag' && snapshot_log staging &&
    run_script deploy.sh rollback staging && expect_rc 1 &&
    expect_err 'releases.log' &&
    expect "bad last tag: no docker call" [ ! -s "$FAKE_CALLS" ] &&
    expect "bad last tag: releases.log unchanged" log_unchanged staging
}

case_gate_shares_one_deadline() {
  local start elapsed
  seed_log staging sha-1111111
  export FAKE_CURL_FAIL=1 GATE_INTERVAL=1 GATE_TIMEOUT=3
  export HEALTH_URLS="http://127.0.0.1:9/a http://127.0.0.1:9/b http://127.0.0.1:9/c"
  start=$SECONDS
  run_script deploy.sh up staging sha-2222222
  elapsed=$((SECONDS - start))
  expect_rc 1 &&
    expect "three failing URLs share one deadline: gate took ${elapsed}s, must be under 7s" [ "$elapsed" -lt 7 ] &&
    expect_err 'gate failed, restored sha-1111111'
}

case_curl_argv_is_hardened() {
  seed_log staging sha-1111111 &&
    run_script smoke.sh http://127.0.0.1:9/c && expect_rc 0 &&
    run_script deploy.sh up staging sha-abcdef1 && expect_rc 0 &&
    expect "every curl call has --max-redirs 0 and a url after --url" curl_calls_are_hardened &&
    expect "smoke passes its url after --url" grep -Fq -- '--url http://127.0.0.1:9/c' "$FAKE_CALLS" &&
    expect "the health gate passes its url after --url" grep -Fq -- '--url http://127.0.0.1:9/health/ready' "$FAKE_CALLS"
}

# --- helpers for the cases below ---

# run_forced_command ARG...: runs a temp copy of forced-command.sh placed next to the fake deploy.sh in
# $W/fc. The wrapper must run that sibling, never a DEPLOY_SCRIPT override.
run_forced_command() {
  RC=0
  if [ ! -f "$deploy_dir/forced-command.sh" ]; then
    echo "    missing script: infra/deploy/forced-command.sh" >&2
    return 1
  fi
  cp "$deploy_dir/forced-command.sh" "$W/fc/forced-command.sh" || return 1
  bash "$W/fc/forced-command.sh" "$@" >"$W/out" 2>"$W/err" </dev/null || RC=$?
}

# DEPLOY_CONFIG is read by deploy-forced and exists for these tests only. Production sets none, so the
# wrapper reads /etc/sonora/deploy.env. Each case writes its own config to $W/deploy.env.

# write_deploy_config LINE...: writes $W/deploy.env, one argument per line. deploy-forced parses it as data.
write_deploy_config() {
  : >"$W/deploy.env"
  for line in "$@"; do
    printf '%s\n' "$line" >>"$W/deploy.env"
  done
}

# write_full_deploy_config: a valid config with every accepted key, plus a comment and a blank line.
write_full_deploy_config() {
  write_deploy_config \
    '# sonora deploy settings (test fixture)' \
    '' \
    "SONORA_ROOT=$W/root" \
    'IMAGE_REPO=registry.example.test/sonora' \
    'MODULES=identity catalog' \
    'HEALTH_URLS_STAGING=http://127.0.0.1:9/staging/ready' \
    'HEALTH_URLS_PRODUCTION=http://127.0.0.1:9/production/ready'
}

# run_deploy_forced ARG...: runs a temp copy of deploy-forced in $W/fdf, next to a fake forced-command.sh
# that dumps its environment (dump-env.txt) and argv (dump-argv.txt) into that folder. The caller
# environment is hostile, as an ssh client might try to make it: GATE_TIMEOUT, DOCKER_HOST,
# DEPLOY_SCRIPT, HEALTH_URLS, SONORA_ROOT and MODULES must not reach forced-command.sh.
run_deploy_forced() {
  RC=0
  rm -f "$W/fdf/dump-env.txt" "$W/fdf/dump-argv.txt"
  if [ ! -f "$deploy_dir/deploy-forced" ]; then
    echo "    missing script: infra/deploy/deploy-forced" >&2
    return 1
  fi
  cp "$deploy_dir/deploy-forced" "$W/fdf/deploy-forced" || return 1
  (
    cd "$W/fdf" &&
      env GATE_TIMEOUT=0 DOCKER_HOST=tcp://evil.example.test:2375 DEPLOY_SCRIPT=/evil/deploy.sh \
        HEALTH_URLS=http://evil.example.test/ready SONORA_ROOT=/evil MODULES=evil \
        DEPLOY_CONFIG="$W/deploy.env" SSH_ORIGINAL_COMMAND="${SSH_ORIGINAL_COMMAND:-}" \
        bash "$W/fdf/deploy-forced" "$@"
  ) >"$W/out" 2>"$W/err" </dev/null || RC=$?
}

# dumped_env_names: the variables forced-command.sh received, minus the ones bash adds for itself.
dumped_env_names() {
  sed 's/=.*//' "$W/fdf/dump-env.txt" 2>/dev/null | grep -vxE '_|PWD|OLDPWD|SHLVL' | LC_ALL=C sort | paste -sd ' ' -
}

# dumped_argv: the argument forced-command.sh received.
dumped_argv() {
  cat "$W/fdf/dump-argv.txt" 2>/dev/null
}

# dump_has LINE: forced-command.sh's environment holds exactly LINE (NAME=value).
dump_has() {
  grep -Fqx -- "$1" "$W/fdf/dump-env.txt" 2>/dev/null
}

# nothing_ran: forced-command.sh was never started (no dump was written).
nothing_ran() {
  [ ! -e "$W/fdf/dump-env.txt" ] && [ ! -e "$W/fdf/dump-argv.txt" ]
}

# expect_rejected MESSAGE: the last run_deploy_forced exited 126, printed 'deploy-forced: rejected' and ran nothing.
expect_rejected() {
  expect "$1: exit 126, got $RC" [ "$RC" -eq 126 ] &&
    expect "$1: 'deploy-forced: rejected' on stderr" grep -Fq 'deploy-forced: rejected' "$W/err" &&
    expect "$1: forced-command.sh did not run" nothing_ran
}

# age_lock ENV: makes the lock directory look old (2000-01-01), so it is no longer a young lock.
age_lock() {
  touch -t 200001010000 "$(lock_dir "$1")"
}

# curl_calls_have TEXT: every curl call recorded in FAKE_CALLS contains the fixed TEXT.
curl_calls_have() {
  local total matching
  total=$(calls_count '^curl ')
  matching=$(grep -E '^curl ' "$FAKE_CALLS" | grep -Fc -- "$1") || true
  [ "$total" -ge 1 ] && [ "$matching" -eq "$total" ]
}

# start_deploy ARG...: runs deploy.sh in the background with job control on, so that SIGINT is not
# inherited as ignored. Output goes to $W/out and $W/err; the pid is BG_PID.
start_deploy() {
  if [ ! -f "$deploy_dir/deploy.sh" ]; then
    echo "    missing script: infra/deploy/deploy.sh" >&2
    return 1
  fi
  set -m
  bash "$deploy_dir/deploy.sh" "$@" >"$W/out" 2>"$W/err" </dev/null &
  BG_PID=$!
  set +m
}

# wait_for_call PATTERN: waits up to 10 seconds for a recorded fake docker or curl call matching PATTERN.
wait_for_call() {
  local i=0
  while [ "$i" -lt 50 ]; do
    if grep -qE -- "$1" "$FAKE_CALLS" 2>/dev/null; then
      return 0
    fi
    sleep 0.2
    i=$((i + 1))
  done
  echo "    timed out waiting for a call matching: $1" >&2
  return 1
}

# finish_deploy: waits for the background deploy and sets RC to its exit status.
finish_deploy() {
  RC=0
  wait "$BG_PID" || RC=$?
}

# signal_during_gate SIGNAL: the new tag never answers, so the gate is still waiting when SIGNAL arrives.
# The previous tag must come back, once, without migrations, and without a releases.log entry.
signal_during_gate() {
  seed_log staging sha-1111111 && snapshot_log staging &&
    export FAKE_CURL_FAIL_AFTER_TAG=sha-2222222 GATE_TIMEOUT=30 &&
    start_deploy up staging sha-2222222 || return 1
  wait_for_call '^curl ' || return 1
  kill -"$1" "$BG_PID"
  finish_deploy
  expect "exit status non-zero after SIG$1, got $RC" [ "$RC" -ne 0 ] &&
    expect "two up -d runs: the new tag, then the previous tag" [ "$(tags_of "$UP" | paste -sd ' ' -)" = "sha-2222222 sha-1111111" ] &&
    expect "migrations ran once, not again on restore" [ "$(calls_count "$MIGRATE")" -eq 11 ] &&
    expect "releases.log is unchanged" log_unchanged staging &&
    expect "the lock is released" [ ! -e "$(lock_dir staging)" ]
}

# --- lock cases ---

case_lock_young_without_pid_blocks_deploy() {
  local variant
  seed_log staging sha-1111111 || return 1
  for variant in missing empty; do
    rm -rf "$(lock_dir staging)"
    : >"$FAKE_CALLS"
    mkdir "$(lock_dir staging)" || return 1
    if [ "$variant" = empty ]; then : >"$(lock_dir staging)/pid"; fi
    run_script deploy.sh up staging sha-abcdef1
    expect_rc 1 || return 1
    expect_err 'another deploy is running' || return 1
    expect "no docker call while a young lock with a $variant pid is held" [ ! -s "$FAKE_CALLS" ] || return 1
    expect "the young lock with a $variant pid is left in place" [ -d "$(lock_dir staging)" ] || return 1
  done
}

case_lock_old_without_pid_is_taken_over() {
  local variant
  seed_log staging sha-1111111 || return 1
  for variant in missing empty; do
    rm -rf "$(lock_dir staging)"
    : >"$FAKE_CALLS"
    rm -f "$W/lock_seen"
    mkdir "$(lock_dir staging)" || return 1
    if [ "$variant" = empty ]; then : >"$(lock_dir staging)/pid"; fi
    age_lock staging || return 1
    export FAKE_LOCK_DIR="$(lock_dir staging)"
    run_script deploy.sh up staging sha-abcdef1
    expect_rc 0 || return 1
    expect "the deploy ran and took the old lock with a $variant pid" [ "$(calls_count "$MIGRATE")" -ge 1 ] || return 1
    expect "the lock was held during the docker calls with a $variant pid" lock_held_during_deploy || return 1
    expect "the lock is gone afterwards with a $variant pid" [ ! -e "$(lock_dir staging)" ] || return 1
  done
}

# The takeover reads a stale lock (dead pid), then another deploy rewrites the pid before the lock is
# moved aside. The moved lock is not the one read, so it must be put back and the deploy must exit 1.
case_takeover_puts_back_a_lock_it_did_not_read() {
  local dead racer ok=0
  seed_log staging sha-1111111 || return 1
  sleep 0 &
  dead=$!
  wait "$dead"
  sleep 30 &
  racer=$!
  if ! { mkdir "$(lock_dir staging)" && printf '%s\n' "$dead" >"$(lock_dir staging)/pid"; }; then
    kill "$racer" 2>/dev/null
    return 1
  fi
  age_lock staging
  export FAKE_MV_RACE="$(lock_dir staging)" FAKE_RACE_PID="$racer"
  run_script deploy.sh up staging sha-abcdef1
  expect_rc 1 &&
    expect "the racing owner's lock is back in place" [ "$(cat "$(lock_dir staging)/pid" 2>/dev/null)" = "$racer" ] &&
    expect "no docker call happened" [ ! -s "$FAKE_CALLS" ] &&
    expect "no copy of the lock is left beside it" [ -z "$(find "$W/root/staging" -name '.deploy.lock*' ! -name .deploy.lock)" ] ||
    ok=1
  kill "$racer" 2>/dev/null
  wait "$racer" 2>/dev/null
  return "$ok"
}

# --- signal cases ---

# A stderr pipe whose reader is gone makes every write fail with EPIPE. A dropped ssh session must not
# stop the deploy: it still migrates, starts the containers and records the release.
case_closed_stderr_does_not_abort_deploy() {
  seed_log staging sha-1111111 || return 1
  bash -c 'exec 2> >(exit 0); sleep 0.3; exec bash "$0" "$@"' "$deploy_dir/deploy.sh" up staging sha-abcdef1 \
    >"$W/out" 2>/dev/null </dev/null
  RC=$?
  expect_rc 0 &&
    expect "containers were started" [ "$(calls_count "$UP")" -ge 1 ] &&
    expect "releases.log gained sha-abcdef1" last_log_entry_is staging sha-abcdef1
}

case_hup_during_gate_is_ignored() {
  seed_log staging sha-1111111 && snapshot_log staging &&
    export FAKE_CURL_FAIL_AFTER_TAG=sha-2222222 &&
    start_deploy up staging sha-2222222 || return 1
  wait_for_call '^curl ' || return 1
  kill -HUP "$BG_PID"
  finish_deploy
  expect_rc 1 &&
    expect_err 'gate failed, restored sha-1111111' &&
    expect "two up -d runs: the new tag, then the previous tag" [ "$(tags_of "$UP" | paste -sd ' ' -)" = "sha-2222222 sha-1111111" ] &&
    expect "releases.log is unchanged" log_unchanged staging
}

case_term_during_gate_restores_previous() {
  signal_during_gate TERM
}

case_int_during_gate_restores_previous() {
  signal_during_gate INT
}

case_term_during_migration_starts_nothing() {
  seed_log staging sha-1111111 && snapshot_log staging &&
    export FAKE_MIGRATE_SLEEP=3 &&
    start_deploy up staging sha-2222222 || return 1
  wait_for_call "$MIGRATE" || return 1
  kill -TERM "$BG_PID"
  finish_deploy
  expect "exit status non-zero, got $RC" [ "$RC" -ne 0 ] &&
    expect "no pull or up -d started" [ "$(calls_count 'pull |up -d ')" -eq 0 ] &&
    expect "at most the first migration started" [ "$(calls_count "$MIGRATE")" -le 1 ] &&
    expect "releases.log is unchanged" log_unchanged staging &&
    expect "the lock is released" [ ! -e "$(lock_dir staging)" ]
}

# --- health gate and smoke: only HTTP 200 is healthy ---

case_smoke_only_200_is_healthy() {
  export SMOKE_TIMEOUT=0 FAKE_CURL_CODE=302 &&
    run_script smoke.sh http://127.0.0.1:9/c && expect_rc 1 || return 1
  export FAKE_CURL_CODE=204 &&
    run_script smoke.sh http://127.0.0.1:9/c && expect_rc 1 || return 1
  export FAKE_CURL_CODE=200 &&
    run_script smoke.sh http://127.0.0.1:9/c && expect_rc 0
}

case_gate_passes_only_on_http_200() {
  local code
  export GATE_TIMEOUT=0
  for code in 204 301 302 404 500; do
    seed_log staging sha-1111111 && snapshot_log staging && : >"$FAKE_CALLS" &&
      export FAKE_CURL_CODE=$code &&
      run_script deploy.sh up staging sha-2222222 || return 1
    expect "HTTP $code keeps the gate failing, got exit $RC" [ "$RC" -eq 1 ] || return 1
    expect "HTTP $code restores sha-1111111" [ "$(tags_of "$UP" | paste -sd ' ' -)" = "sha-2222222 sha-1111111" ] || return 1
    expect "HTTP $code leaves releases.log unchanged" log_unchanged staging || return 1
  done
  seed_log staging sha-1111111 && : >"$FAKE_CALLS" && export FAKE_CURL_CODE=200 &&
    run_script deploy.sh up staging sha-2222222 || return 1
  expect_rc 0 && expect "HTTP 200 passes the gate and records sha-2222222" last_log_entry_is staging sha-2222222
}

case_curl_asks_for_http_code_and_time_limit() {
  seed_log staging sha-1111111 &&
    run_script smoke.sh http://127.0.0.1:9/c && expect_rc 0 &&
    run_script deploy.sh up staging sha-abcdef1 && expect_rc 0 &&
    expect "curl was called" [ "$(calls_count '^curl ')" -ge 2 ] &&
    expect "every curl call has -w %{http_code}" curl_calls_have '-w %{http_code}' &&
    expect "every curl call has --max-time 10" curl_calls_have '--max-time 10'
}

# --- forced command: DEPLOY_SCRIPT is ignored ---

case_forced_command_ignores_deploy_script_env() {
  printf '#!/usr/bin/env bash\n: >"$FAKE_STATE/marker-ran"\n' >"$W/marker.sh" && chmod +x "$W/marker.sh" &&
    export DEPLOY_SCRIPT="$W/marker.sh" SSH_ORIGINAL_COMMAND='deploy up staging sha-abcdef1' &&
    rm -f "$W/deploy-args" && run_forced_command staging && expect_rc 0 &&
    expect "the sibling deploy.sh ran with the bound arguments" [ "$(cat "$W/deploy-args" 2>/dev/null)" = 'up staging sha-abcdef1' ] &&
    expect "the DEPLOY_SCRIPT marker did not run" [ ! -e "$W/marker-ran" ]
}

# --- deploy-forced: the environment-bound wrapper ---

case_deploy_forced_staging_happy() {
  write_full_deploy_config &&
    export SSH_ORIGINAL_COMMAND='deploy up staging sha-abcdef1' &&
    run_deploy_forced staging && expect_rc 0 &&
    expect "argv is the bound environment only, got: $(dumped_argv)" [ "$(dumped_argv)" = staging ] &&
    expect "environment holds only the allowed names, got: $(dumped_env_names)" \
      [ "$(dumped_env_names)" = 'HEALTH_URLS IMAGE_REPO MODULES PATH SONORA_ROOT SSH_ORIGINAL_COMMAND' ] &&
    expect "PATH is the wrapper's fixed PATH" dump_has 'PATH=/usr/local/bin:/usr/bin:/bin' &&
    expect "SONORA_ROOT comes from the config, not the caller" dump_has "SONORA_ROOT=$W/root" &&
    expect "IMAGE_REPO comes from the config" dump_has 'IMAGE_REPO=registry.example.test/sonora' &&
    expect "HEALTH_URLS is the staging list from the config" dump_has 'HEALTH_URLS=http://127.0.0.1:9/staging/ready' &&
    expect "MODULES comes from the config, not the caller" dump_has 'MODULES=identity catalog' &&
    expect "SSH_ORIGINAL_COMMAND passes through unchanged" dump_has 'SSH_ORIGINAL_COMMAND=deploy up staging sha-abcdef1'
}

case_deploy_forced_production_happy() {
  write_deploy_config \
    "SONORA_ROOT=$W/root" \
    'IMAGE_REPO=registry.example.test/sonora' \
    'HEALTH_URLS_PRODUCTION=http://127.0.0.1:9/production/ready' &&
    export SSH_ORIGINAL_COMMAND='deploy rollback production' &&
    run_deploy_forced production && expect_rc 0 &&
    expect "argv is production, got: $(dumped_argv)" [ "$(dumped_argv)" = production ] &&
    expect "no MODULES configured, so none is passed, got: $(dumped_env_names)" \
      [ "$(dumped_env_names)" = 'HEALTH_URLS IMAGE_REPO PATH SONORA_ROOT SSH_ORIGINAL_COMMAND' ] &&
    expect "HEALTH_URLS is the production list" dump_has 'HEALTH_URLS=http://127.0.0.1:9/production/ready' &&
    expect "SSH_ORIGINAL_COMMAND passes through unchanged" dump_has 'SSH_ORIGINAL_COMMAND=deploy rollback production'
}

case_deploy_forced_rejects_bad_env_argument() {
  local arg
  write_full_deploy_config && export SSH_ORIGINAL_COMMAND='deploy rollback staging' || return 1
  run_deploy_forced && expect_rejected "no argument" || return 1
  for arg in '' qa Staging 'staging production' 'staging;id' 'production-eu'; do
    run_deploy_forced "$arg" && expect_rejected "argument [$arg]" || return 1
  done
  run_deploy_forced staging extra && expect_rejected "two arguments" || return 1
}

case_deploy_forced_rejects_missing_config() {
  write_full_deploy_config && rm -f "$W/deploy.env" &&
    export SSH_ORIGINAL_COMMAND='deploy up staging sha-abcdef1' &&
    run_deploy_forced staging && expect_rejected "missing config file"
}

case_deploy_forced_rejects_unknown_keys_and_malformed_lines() {
  local extra
  export SSH_ORIGINAL_COMMAND='deploy up staging sha-abcdef1'
  for extra in 'GATE_TIMEOUT=0' 'DOCKER_HOST=tcp://evil.example.test:2375' 'DEPLOY_SCRIPT=/evil/deploy.sh' \
    'HEALTH_URLS=http://evil.example.test/ready' 'SONORA_ROOT' 'just some words'; do
    write_full_deploy_config && printf '%s\n' "$extra" >>"$W/deploy.env" &&
      run_deploy_forced staging && expect_rejected "config line [$extra]" || return 1
  done
}

case_deploy_forced_rejects_bad_values_and_never_sources_config() {
  local value
  export SSH_ORIGINAL_COMMAND='deploy up staging sha-abcdef1'
  for value in 'registry.example.test/$HOME' 'registry.example.test/`id`' 'registry.example.test/a"b' \
    "registry.example.test/a'b" 'registry.example.test/a;id' 'registry.example.test/a&id' \
    'registry.example.test/a|id' 'registry.example.test/a\b' "registry.example.test/\$(touch $W/pwned)"; do
    write_deploy_config "SONORA_ROOT=$W/root" "IMAGE_REPO=$value" 'HEALTH_URLS_STAGING=http://127.0.0.1:9/staging/ready' &&
      run_deploy_forced staging && expect_rejected "IMAGE_REPO=[$value]" || return 1
  done
  for value in 'http://127.0.0.1:9/a;id' 'http://127.0.0.1:9/$HOME'; do
    write_deploy_config "SONORA_ROOT=$W/root" 'IMAGE_REPO=registry.example.test/sonora' "HEALTH_URLS_STAGING=$value" &&
      run_deploy_forced staging && expect_rejected "HEALTH_URLS_STAGING=[$value]" || return 1
  done
  write_deploy_config "SONORA_ROOT=$W/root" 'IMAGE_REPO=registry.example.test/sonora' \
    'HEALTH_URLS_STAGING=http://127.0.0.1:9/staging/ready' 'HEALTH_URLS_PRODUCTION=http://127.0.0.1:9/a;id' &&
    run_deploy_forced staging && expect_rejected "a bad production URL is rejected while staging runs" || return 1
  expect "the config was never executed: no marker file" [ ! -e "$W/pwned" ]
}

# HEALTH_URLS in the caller environment must not satisfy the config's requirement for the bound env.
case_deploy_forced_rejects_missing_required_keys() {
  export SSH_ORIGINAL_COMMAND='deploy up staging sha-abcdef1'
  write_deploy_config 'IMAGE_REPO=registry.example.test/sonora' 'HEALTH_URLS_STAGING=http://127.0.0.1:9/staging/ready' &&
    run_deploy_forced staging && expect_rejected "SONORA_ROOT missing" || return 1
  write_deploy_config "SONORA_ROOT=$W/root" 'HEALTH_URLS_STAGING=http://127.0.0.1:9/staging/ready' &&
    run_deploy_forced staging && expect_rejected "IMAGE_REPO missing" || return 1
  write_deploy_config "SONORA_ROOT=$W/root" 'IMAGE_REPO=registry.example.test/sonora' &&
    run_deploy_forced staging && expect_rejected "HEALTH_URLS_STAGING missing" || return 1
  write_deploy_config "SONORA_ROOT=$W/root" 'IMAGE_REPO=registry.example.test/sonora' \
    'HEALTH_URLS_STAGING=http://127.0.0.1:9/staging/ready' &&
    export SSH_ORIGINAL_COMMAND='deploy rollback production' &&
    run_deploy_forced production && expect_rejected "HEALTH_URLS_PRODUCTION missing for production" || return 1
}

run_case() {
  local name="$1" fn="$2" rc=0 output
  output=$(mktemp) || { echo "FAIL $name"; failures=$((failures + 1)); return; }
  (
    W=$(mktemp -d) || exit 1
    trap 'rm -rf "$W"' EXIT
    setup_sandbox
    "$fn"
  ) >"$output" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "PASS $name"
  else
    echo "FAIL $name"
    sed 's/^/  /' "$output"
    failures=$((failures + 1))
  fi
  rm -f "$output"
}

run_case "smoke ok" case_smoke_ok
run_case "smoke timeout" case_smoke_timeout
run_case "up success: migrations, then pull and up, then log" case_up_success
run_case "migration failure aborts before pull and up" case_migration_failure_aborts
run_case "gate failure restores previous, no migrations rerun" case_gate_failure_restores_previous
run_case "gate failure with no previous release" case_gate_failure_without_previous
run_case "rollback picks second-to-last and appends" case_rollback_uses_second_to_last
run_case "rollback with one log line fails" case_rollback_with_one_line_fails
run_case "deploy rejects bad tag and unknown env" case_rejects_bad_tag_and_env
run_case "forced command accepts allowed forms" case_forced_command_accepts_allowed_forms
run_case "forced command rejects hostile commands" case_forced_command_rejects_hostile_commands
run_case "forced command: staging key rejects production commands" case_forced_command_staging_key_rejects_production
run_case "forced command: production key rejects staging commands" case_forced_command_production_key_rejects_staging
run_case "forced command: no or invalid env argument is rejected" case_forced_command_needs_valid_env_argument
run_case "forced command: production key accepts production forms" case_forced_command_production_key_accepts_production
run_case "lock: a live pid blocks the deploy" case_lock_held_by_live_pid_blocks_deploy
run_case "lock: a dead pid is taken over and held during the deploy" case_lock_with_dead_pid_is_taken_over
run_case "lock: held during the deploy and released after success" case_lock_released_after_success
run_case "lock: released after failure" case_lock_released_after_failure
run_case "releases.log: invalid previous tag stops up" case_up_rejects_invalid_previous_tag
run_case "releases.log: invalid tag stops rollback" case_rollback_rejects_invalid_tags
run_case "health gate: all URLs share one deadline" case_gate_shares_one_deadline
run_case "curl calls use --max-redirs 0 and pass the url after --url" case_curl_argv_is_hardened
run_case "smoke: only HTTP 200 counts as healthy" case_smoke_only_200_is_healthy
run_case "lock: a young lock with no pid blocks the deploy" case_lock_young_without_pid_blocks_deploy
run_case "lock: an old lock with no pid is taken over" case_lock_old_without_pid_is_taken_over
run_case "lock: takeover puts back a lock it did not read" case_takeover_puts_back_a_lock_it_did_not_read
run_case "signals: a closed stderr pipe does not abort the deploy" case_closed_stderr_does_not_abort_deploy
run_case "signals: HUP during the health gate is ignored" case_hup_during_gate_is_ignored
run_case "signals: TERM during the health gate restores the previous release" case_term_during_gate_restores_previous
run_case "signals: INT during the health gate restores the previous release" case_int_during_gate_restores_previous
run_case "signals: TERM during migrations starts nothing and releases the lock" case_term_during_migration_starts_nothing
run_case "health gate: only HTTP 200 passes" case_gate_passes_only_on_http_200
run_case "curl asks for the http code with -w and --max-time" case_curl_asks_for_http_code_and_time_limit
run_case "forced command: DEPLOY_SCRIPT is ignored, the sibling deploy.sh runs" case_forced_command_ignores_deploy_script_env
run_case "deploy-forced: staging happy path passes only the allowed environment" case_deploy_forced_staging_happy
run_case "deploy-forced: production happy path" case_deploy_forced_production_happy
run_case "deploy-forced: missing or invalid env argument is rejected" case_deploy_forced_rejects_bad_env_argument
run_case "deploy-forced: missing config file is rejected" case_deploy_forced_rejects_missing_config
run_case "deploy-forced: unknown keys and malformed lines are rejected" case_deploy_forced_rejects_unknown_keys_and_malformed_lines
run_case "deploy-forced: bad values are rejected and the config is never sourced" case_deploy_forced_rejects_bad_values_and_never_sources_config
run_case "deploy-forced: missing required keys are rejected" case_deploy_forced_rejects_missing_required_keys

if [ "$failures" -gt 0 ]; then
  echo "$failures case(s) failed"
  exit 1
fi
echo "all deploy tests passed"
