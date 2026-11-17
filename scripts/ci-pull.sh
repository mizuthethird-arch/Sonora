#!/usr/bin/env bash
# Pulls the compose images for the given services. A failed pull is retried once, with a GitHub warning first.
set -euo pipefail

cd "$(dirname "$0")/.."

readonly PULL_ATTEMPTS=2

pull_images() {
  docker compose -f docker-compose.yml pull "$@"
}

# Tries the pull up to PULL_ATTEMPTS times and returns non-zero when every attempt fails.
pull_with_retry() {
  local attempt
  for attempt in $(seq 1 "$PULL_ATTEMPTS"); do
    if pull_images "$@"; then
      return 0
    fi
    if [ "$attempt" -lt "$PULL_ATTEMPTS" ]; then
      echo "::warning::image pull failed, retrying once"
    fi
  done
  echo "image pull failed after $PULL_ATTEMPTS attempts: $*" >&2
  return 1
}

main() {
  if [ "$#" -eq 0 ]; then
    echo "usage: ci-pull.sh <service>..." >&2
    exit 2
  fi
  pull_with_retry "$@"
}

main "$@"
