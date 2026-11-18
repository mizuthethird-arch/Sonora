#!/usr/bin/env bash
# Tests for infra/deploy/deploy.sh, smoke.sh and forced-command.sh.
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
  cat >"$W/bin/docker" <<'EOF'
#!/usr/bin/env bash
# Fake docker. Records every call with the SONORA_TAG and IMAGE_REPO it ran with.
# FAKE_MIGRATE_FAIL=all fails every migrate run; any other value fails only that module.
printf 'SONORA_TAG=%s IMAGE_REPO=%s docker %s\n' "${SONORA_TAG:-}" "${IMAGE_REPO:-}" "$*" >>"$FAKE_CALLS"
if [ -n "${SONORA_TAG:-}" ]; then
  printf '%s\n' "$SONORA_TAG" >"$FAKE_STATE/last_tag"
fi
case " $* " in
  *" run "*)
    module=""
    for arg in "$@"; do module=$arg; done
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
# Fake curl. Fails when FAKE_CURL_FAIL=1, or while the last SONORA_TAG docker ran with
# equals FAKE_CURL_FAIL_AFTER_TAG.
printf 'curl %s\n' "$*" >>"$FAKE_CALLS"
if [ "${FAKE_CURL_FAIL:-0}" = 1 ]; then
  exit 22
fi
if [ -n "${FAKE_CURL_FAIL_AFTER_TAG:-}" ] && [ -f "$FAKE_STATE/last_tag" ] &&
  [ "$(cat "$FAKE_STATE/last_tag")" = "$FAKE_CURL_FAIL_AFTER_TAG" ]; then
  exit 22
fi
exit 0
EOF
  cat >"$W/fake-deploy.sh" <<'EOF'
#!/usr/bin/env bash
# Stands in for deploy.sh: records the arguments forced-command.sh passed.
printf '%s\n' "$*" >"$FAKE_STATE/deploy-args"
EOF
  chmod +x "$W/bin/docker" "$W/bin/curl" "$W/fake-deploy.sh"
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
  export DEPLOY_SCRIPT="$W/fake-deploy.sh"
  unset MODULES SONORA_TAG SSH_ORIGINAL_COMMAND FAKE_MIGRATE_FAIL FAKE_CURL_FAIL FAKE_CURL_FAIL_AFTER_TAG
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
  local cmd
  for cmd in 'deploy up staging sha-abcdef1' 'deploy up production v1.2.3' \
    'deploy rollback staging' 'deploy rollback production'; do
    rm -f "$W/deploy-args"
    export SSH_ORIGINAL_COMMAND="$cmd"
    run_script forced-command.sh || return 1
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
    run_script forced-command.sh || return 1
    expect "rejects [$cmd] with exit 126 (got $RC)" [ "$RC" -eq 126 ] || return 1
    expect "rejects [$cmd] with 'rejected' on stderr" grep -qi rejected "$W/err" || return 1
    expect "rejects [$cmd] and runs nothing" [ ! -e "$W/deploy-args" ] || return 1
  done
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

if [ "$failures" -gt 0 ]; then
  echo "$failures case(s) failed"
  exit 1
fi
echo "all deploy tests passed"
