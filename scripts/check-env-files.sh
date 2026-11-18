#!/usr/bin/env bash
# Rejects any env file that git tracks, except .env.example. Secrets stay out of the repository.
# Usage: scripts/check-env-files.sh [--staged] [repository-dir]
#   --staged  checks only the files staged for the next commit (used by the pre-commit hook).
set -euo pipefail

mode="tracked"
if [ "${1:-}" = "--staged" ]; then
  mode="staged"
  shift
fi
repo="${1:-.}"

list_files() {
  if [ "$mode" = "staged" ]; then
    git -C "$repo" diff --cached --name-only --diff-filter=ACMR
  else
    git -C "$repo" ls-files
  fi
}

forbidden=$(list_files | grep -E '(^|/)\.env(\..*)?$' | grep -vE '(^|/)\.env\.example$' || true)

if [ -n "$forbidden" ]; then
  echo "rejected: an env file is tracked or staged. Only .env.example may be committed:" >&2
  printf '%s\n' "$forbidden" >&2
  exit 1
fi
echo "env files: ok"
