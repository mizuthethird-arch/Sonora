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

# Prints the raw text after the last MEILI_MASTER_KEY= line, trimmed of surrounding
# whitespace only. Quotes are kept so that check_meili_master_key can reject them.
read_raw_meili_key() {
  local file="$1" line
  line=$(grep -E "^MEILI_MASTER_KEY=" "$file" | tail -n 1 || true)
  line="${line#MEILI_MASTER_KEY=}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  printf '%s' "$line"
}

# Rejects a non-empty MEILI_MASTER_KEY that is shorter than the minimum (counted in bytes)
# or contains anything outside the allow-list. Never prints the value.
check_meili_master_key() {
  local file="$1" value bytes
  value=$(read_raw_meili_key "$file")
  [[ -z "$value" ]] && return 0
  bytes=$(printf '%s' "$value" | LC_ALL=C wc -c | tr -d ' ')
  if [[ "$bytes" -lt "$MEILI_MASTER_KEY_MIN_LENGTH" ]]; then
    echo "check-env: MEILI_MASTER_KEY in $file must be at least $MEILI_MASTER_KEY_MIN_LENGTH characters" >&2
    problems=$((problems + 1))
    return 0
  fi
  if LC_ALL=C grep -q '[^A-Za-z0-9_.-]' <<<"$value"; then
    echo "check-env: MEILI_MASTER_KEY in $file may only contain letters A-Z a-z, digits 0-9, and _ - ." >&2
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
  check_meili_master_key "$file"
  if [[ "$problems" -gt 0 ]]; then
    return 1
  fi
  echo "check-env: $file has all required keys"
  return 0
}

main "$@"
