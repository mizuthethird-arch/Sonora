#!/usr/bin/env bash
# SSH forced command for the deploy user. The key is bound to one environment, given as the
# only argument: forced-command.sh <staging|production>.
# Allows exactly two shapes of SSH_ORIGINAL_COMMAND, and only for that environment:
#   deploy up <env> <tag>
#   deploy rollback <env>
# Anything else exits 126 and runs nothing. Allowed commands exec DEPLOY_SCRIPT
# (default: deploy.sh next to this file) with the arguments after "deploy".
set -euo pipefail

ALLOWED_RE='^deploy (up (staging|production) (sha-[0-9a-f]{7,40}|v[0-9]+\.[0-9]+\.[0-9]+)|rollback (staging|production))$'
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEPLOY_SCRIPT="${DEPLOY_SCRIPT:-$script_dir/deploy.sh}"

# reject: refuses the command with exit 126; nothing runs.
reject() {
  echo "forced-command: rejected" >&2
  exit 126
}

# valid_env ENV: succeeds only for staging and production.
valid_env() {
  case "$1" in
    staging | production) return 0 ;;
    *) return 1 ;;
  esac
}

main() {
  local bound_env="${1:-}"
  local cmd="${SSH_ORIGINAL_COMMAND:-}"
  local -a words
  [ $# -eq 1 ] || reject
  valid_env "$bound_env" || reject
  if ! [[ $cmd =~ $ALLOWED_RE ]]; then
    reject
  fi
  # The whole string matched ALLOWED_RE, so it is plain single-space-separated tokens.
  read -r -a words <<<"$cmd"
  # words[2] is the environment the command names; it must be the one this key is bound to.
  if [ "${words[2]}" != "$bound_env" ]; then
    reject
  fi
  exec "$DEPLOY_SCRIPT" "${words[@]:1}"
}

main "$@"
