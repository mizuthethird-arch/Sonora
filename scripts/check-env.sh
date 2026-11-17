#!/usr/bin/env bash
# Checks that the env file exists and that every required key is set.
# Never prints values. Usage: ./scripts/check-env.sh [env-file]   (default: .env)
set -euo pipefail

readonly DEFAULT_ENV_FILE=".env"
readonly REQUIRED_KEYS=(MODULE_DB_PASSWORD)

problems=0

# Prints the value of KEY from FILE (last match wins), without whitespace or quotes.
read_value() {
  local file="$1" key="$2" line
  line=$(grep -E "^${key}=" "$file" | tail -n 1 || true)
  line="${line#"$key"=}"
  line="${line//\"/}"
  line="${line//\'/}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  printf '%s' "$line"
}

check_required_keys() {
  local file="$1" key
  for key in "${REQUIRED_KEYS[@]}"; do
    if [[ -z "$(read_value "$file" "$key")" ]]; then
      echo "check-env: $key is empty in $file" >&2
      problems=$((problems + 1))
    fi
  done
}

main() {
  local file="${1:-$DEFAULT_ENV_FILE}"
  if [[ ! -f "$file" ]]; then
    echo "check-env: $file not found, copy .env.example to .env" >&2
    return 1
  fi
  check_required_keys "$file"
  if [[ "$problems" -gt 0 ]]; then
    return 1
  fi
  echo "check-env: $file has all required keys"
  return 0
}

main "$@"
