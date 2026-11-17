#!/usr/bin/env bash
set -euo pipefail

readonly ENV_FILE=".env"
readonly DENIED_ERROR="ERROR 1044"

MODULES=(identity catalog media playback library search recommender realtime notification analytics platform)

PASS_COUNT=0
FAIL_COUNT=0
FAILED_CHECKS=""

enter_repo_root() {
  cd "$(dirname "$0")/.."
}

fail_fast() {
  echo "check-databases: $1" >&2
  exit 1
}

load_env() {
  [[ -f "$ENV_FILE" ]] || fail_fast "missing $ENV_FILE in repo root; it must set MODULE_DB_PASSWORD"
  set -a
  . "./$ENV_FILE"
  set +a
  [[ -n "${MODULE_DB_PASSWORD:-}" ]] || fail_fast "MODULE_DB_PASSWORD is not set in $ENV_FILE"
}

run_sql() {
  local user="$1" sql="$2"
  docker compose exec -T mysql mysql -u"$user" -p"$MODULE_DB_PASSWORD" -e "$sql" 2>&1
}

record_pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "PASS  $1"
  return 0
}

record_fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAILED_CHECKS="${FAILED_CHECKS}  - $1"$'\n'
  echo "FAIL  $1"
  if [[ -n "${2:-}" ]]; then
    echo "      $2"
  fi
  return 0
}

expect_own_access() {
  local module="$1" desc="${1}_user can USE ${1}" output
  if output=$(run_sql "${module}_user" "USE $module"); then
    record_pass "$desc"
  else
    record_fail "$desc" "$output"
  fi
}

expect_denied() {
  local user="$1" db="$2" desc output status=0
  desc="${user} is denied USE ${db} (${DENIED_ERROR})"
  output=$(run_sql "$user" "USE $db") || status=$?
  if [[ "$status" -eq 0 ]]; then
    record_fail "$desc" "access was granted"
  elif [[ "$output" == *"$DENIED_ERROR"* ]]; then
    record_pass "$desc"
  else
    record_fail "$desc" "$output"
  fi
  return 0
}

is_guard_pair() {
  [[ "$1" == "catalog" && "$2" == "identity" ]]
}

check_guard() {
  local before="$FAIL_COUNT"
  echo "=== GUARD (first check): catalog_user must get ${DENIED_ERROR} on USE identity ==="
  expect_denied catalog_user identity
  if [[ "$FAIL_COUNT" -gt "$before" ]]; then
    echo "!!! GUARD FAILED: catalog_user can reach the identity database. Fix grants before anything else."
  fi
  return 0
}

check_module_access() {
  local module="$1" other
  expect_own_access "$module"
  for other in "${MODULES[@]}"; do
    if [[ "$other" != "$module" ]] && ! is_guard_pair "$module" "$other"; then
      expect_denied "${module}_user" "$other"
    fi
  done
  return 0
}

print_summary() {
  echo ""
  echo "passed: $PASS_COUNT  failed: $FAIL_COUNT"
  if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo "failed checks:"
    printf '%s' "$FAILED_CHECKS"
    return 1
  fi
  return 0
}

main() {
  enter_repo_root
  load_env
  check_guard
  local module
  for module in "${MODULES[@]}"; do
    check_module_access "$module"
  done
  print_summary
}

main "$@"
