#!/usr/bin/env bash
# Applies every Prisma migration to a new empty MySQL database, then runs them again and requires a no-op.
# Prisma creates the database on the first deploy. The EXIT trap drops it, even when a check fails.
set -euo pipefail

cd "$(dirname "$0")/.."

readonly MYSQL_SERVER="mysql://root@mysql:3306"
readonly APPLIED_TEXT="Applying migration"
readonly NO_OP_TEXT="No pending migrations to apply"

database_name=""

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

new_database_name() {
  printf 'dryrun_%s' "$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
}

# Runs one Prisma command in the workspace container against the given database.
run_prisma() {
  local database="$1"
  shift
  docker compose -f docker-compose.yml run --rm -T -e "DATABASE_URL=$MYSQL_SERVER/$database" \
    workspace pnpm --filter @sonora/api exec prisma "$@"
}

deploy_migrations() {
  run_prisma "$1" migrate deploy
}

drop_database() {
  printf 'DROP DATABASE IF EXISTS `%s`' "$1" |
    run_prisma "$1" db execute --stdin >/dev/null 2>&1
}

drop_database_on_exit() {
  if [ -n "$database_name" ] && ! drop_database "$database_name"; then
    printf 'warning: could not drop %s\n' "$database_name" >&2
  fi
}

expect_applied() {
  if grep -Fq "$APPLIED_TEXT" <<<"$1"; then
    echo "PASS  first run applied the migrations"
  else
    echo "FAIL  first run applied no migrations"
    return 1
  fi
}

expect_no_op() {
  if grep -Fq "$NO_OP_TEXT" <<<"$1"; then
    echo "PASS  second run is a no-op"
  else
    echo "FAIL  second run changed the database"
    return 1
  fi
}

main() {
  local first_run second_run failed=0

  database_name=$(new_database_name)
  trap drop_database_on_exit EXIT
  echo "database: $database_name"

  first_run=$(deploy_migrations "$database_name" 2>&1) ||
    { printf '%s\n' "$first_run" >&2; die "first migrate deploy failed"; }
  second_run=$(deploy_migrations "$database_name" 2>&1) ||
    { printf '%s\n' "$second_run" >&2; die "second migrate deploy failed"; }

  expect_applied "$first_run" || failed=1
  expect_no_op "$second_run" || failed=1
  [ "$failed" -eq 0 ] || die "migration dry run failed"
  echo "migration dry run passed"
}

main "$@"
