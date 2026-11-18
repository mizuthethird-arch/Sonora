#!/usr/bin/env bash
# Creates the local stand-in for AWS Secrets Manager: one random database password per module for one environment.
# Usage: scripts/secrets-local.sh init <staging|production>
# Values live in .secrets-local/ (gitignored). Existing values are never overwritten.
set -euo pipefail

cd "$(dirname "$0")/.."

readonly STORE=".secrets-local"
readonly MODULES=(identity catalog media playback library search recommender realtime notification analytics platform)

usage() {
  echo "usage: scripts/secrets-local.sh init <staging|production>" >&2
  exit 2
}

random_password() {
  head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n'
}

init_environment() {
  local environment="$1" directory module file
  directory="$STORE/sonora/$environment/db"
  mkdir -p "$directory"
  chmod 700 "$STORE"
  for module in "${MODULES[@]}"; do
    file="$directory/$module"
    if [ -e "$file" ]; then
      echo "kept   $file"
      continue
    fi
    (umask 077 && random_password > "$file")
    echo "wrote  $file"
  done
}

[ "$#" -eq 2 ] && [ "$1" = "init" ] || usage
case "$2" in
  staging|production) init_environment "$2" ;;
  *) usage ;;
esac
