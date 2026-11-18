#!/usr/bin/env bash
# Runs once when the mysql container starts with an empty data directory.
# Creates one database and one user per module. Development only.
set -euo pipefail

readonly MODULES=(identity catalog media playback library search recommender realtime notification analytics platform)

# Escapes backslashes and single quotes for use inside a single-quoted SQL string.
sql_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/''/g"
}

create_module() {
  local module="$1" password="$2"
  mysql -uroot <<SQL
CREATE DATABASE IF NOT EXISTS \`${module}\`;
CREATE USER IF NOT EXISTS '${module}_user'@'%' IDENTIFIED BY '${password}';
GRANT ALL PRIVILEGES ON \`${module}\`.* TO '${module}_user'@'%';
SQL
}

main() {
  if [[ -z "${MODULE_DB_PASSWORD:-}" ]]; then
    echo "01-module-databases: MODULE_DB_PASSWORD is empty, skipping module databases"
    exit 0
  fi
  local password module
  password=$(sql_escape "$MODULE_DB_PASSWORD")
  for module in "${MODULES[@]}"; do
    create_module "$module" "$password"
  done
  echo "01-module-databases: created ${#MODULES[@]} module databases and users"
}

main "$@"
