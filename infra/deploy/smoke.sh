#!/usr/bin/env bash
# Smoke-checks deployed URLs: all of them must answer within one shared SMOKE_TIMEOUT deadline.
# Usage: smoke.sh [url ...]   (with no arguments, uses the space-separated SMOKE_URLS)
# Environment: SMOKE_TIMEOUT (default 90) and SMOKE_INTERVAL (default 2), in seconds.
# Checks every URL, names each one that never answered, and exits 1 if any failed.
set -euo pipefail

SMOKE_INTERVAL="${SMOKE_INTERVAL:-2}"
SMOKE_TIMEOUT="${SMOKE_TIMEOUT:-90}"

# wait_for_url URL INTERVAL DEADLINE: returns 0 once URL answers, 1 once SECONDS reaches DEADLINE.
# DEADLINE is an absolute $SECONDS value shared by every URL; each URL gets at least one try.
wait_for_url() {
  local url="$1" interval="$2" deadline="$3"
  while ! curl -fsS -o /dev/null --max-time 10 --max-redirs 0 --url "$url"; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      return 1
    fi
    sleep "$interval"
  done
}

main() {
  local url deadline failed=0
  local -a urls
  if [ $# -gt 0 ]; then
    urls=("$@")
  else
    read -r -a urls <<<"${SMOKE_URLS:-}" || true
  fi
  if [ "${#urls[@]}" -eq 0 ]; then
    echo "usage: smoke.sh [url ...]  (or set SMOKE_URLS)" >&2
    exit 2
  fi
  deadline=$((SECONDS + SMOKE_TIMEOUT))
  for url in "${urls[@]}"; do
    if ! wait_for_url "$url" "$SMOKE_INTERVAL" "$deadline"; then
      echo "smoke: $url did not answer within ${SMOKE_TIMEOUT}s" >&2
      failed=$((failed + 1))
    fi
  done
  if [ "$failed" -gt 0 ]; then
    echo "smoke: $failed of ${#urls[@]} url(s) failed" >&2
    exit 1
  fi
  echo "smoke: all ${#urls[@]} url(s) ok" >&2
}

main "$@"
