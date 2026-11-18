#!/usr/bin/env bash
# Checks that the env file exists and that every required key is set.
# Never prints values. Usage: ./scripts/check-env.sh [env-file]   (default: .env)
set -euo pipefail

readonly DEFAULT_ENV_FILE=".env"
readonly REQUIRED_KEYS=(MODULE_DB_PASSWORD MEILI_MASTER_KEY)
readonly MEILI_MASTER_KEY_MIN_LENGTH=16

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

# Rejects a non-empty MEILI_MASTER_KEY shorter than the minimum. Never prints the value.
check_meili_key_length() {
  local file="$1" value
  value=$(read_value "$file" MEILI_MASTER_KEY)
  if [[ -n "$value" && "${#value}" -lt "$MEILI_MASTER_KEY_MIN_LENGTH" ]]; then
    echo "check-env: MEILI_MASTER_KEY in $file must be at least $MEILI_MASTER_KEY_MIN_LENGTH characters" >&2
    problems=$((problems + 1))
  fi
}

main() {
  local file="${1:-$DEFAULT_ENV_FILE}"
  if [[ ! -f "$file" ]]; then
    echo "check-env: $file not found, copy .env.example to .env" >&2
    return 1
  fi
  check_required_keys "$file"
  check_meili_key_length "$file"
  if [[ "$problems" -gt 0 ]]; then
    return 1
  fi
  echo "check-env: $file has all required keys"
  return 0
}

main "$@"
