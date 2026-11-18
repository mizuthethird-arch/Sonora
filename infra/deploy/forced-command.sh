#!/usr/bin/env bash
# SSH forced command for the deploy user. Allows exactly two shapes of SSH_ORIGINAL_COMMAND:
#   deploy up <staging|production> <tag>
#   deploy rollback <staging|production>
# Anything else exits 126 and runs nothing. Allowed commands exec DEPLOY_SCRIPT
# (default: deploy.sh next to this file) with the arguments after "deploy".
set -euo pipefail

ALLOWED_RE='^deploy (up (staging|production) (sha-[0-9a-f]{7,40}|v[0-9]+\.[0-9]+\.[0-9]+)|rollback (staging|production))$'
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEPLOY_SCRIPT="${DEPLOY_SCRIPT:-$script_dir/deploy.sh}"

main() {
  local cmd="${SSH_ORIGINAL_COMMAND:-}"
  local -a words
  if ! [[ $cmd =~ $ALLOWED_RE ]]; then
    echo "forced-command: rejected" >&2
    exit 126
  fi
  # The whole string matched ALLOWED_RE, so it is plain single-space-separated tokens.
  read -r -a words <<<"$cmd"
  exec "$DEPLOY_SCRIPT" "${words[@]:1}"
}

main
