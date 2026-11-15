#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

failures=0
workflow=".github/workflows/ci.yml"

node_image_pattern='^FROM node:[0-9]+\.[0-9]+\.[0-9]+-alpine@sha256:[0-9a-f]{64} AS workspace$'
gitleaks_image_pattern='image: zricethezav/gitleaks:v[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}'
pnpm_version_pattern='"packageManager": "pnpm@[0-9]+\.[0-9]+\.[0-9]+"'
ci_gates_pattern='"ci": ".*audit:dependencies.*lint.*typecheck.*test.*build'
cancel_only_on_pull_requests="cancel-in-progress: \${{ github.event_name == 'pull_request' }}"
action_pinned_to_sha='uses: .*@[0-9a-f]{40}'
action_pinned_to_name='uses: .+@(v[0-9]|main|master|latest)'

check() {
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS  $description"
  else
    echo "FAIL  $description"
    failures=$((failures + 1))
  fi
}

file_matches() {
  grep -Eq "$2" "$1"
}

file_contains() {
  local file="$1"
  shift
  for text in "$@"; do
    grep -Fq -- "$text" "$file" || return 1
  done
}

file_lacks() {
  ! grep -Fq -- "$2" "$1"
}

file_has_lines() {
  local file="$1"
  shift
  for line in "$@"; do
    grep -Fqx -- "$line" "$file" || return 1
  done
}

compose_has_services() {
  local services
  services=$(docker compose --profile tools config --services)
  for service in "$@"; do
    grep -qx "$service" <<<"$services" || return 1
  done
}

bind_mount_only_in_override() {
  file_lacks docker-compose.yml '.:/workspace' || return 1
  file_contains docker-compose.override.yml '.:/workspace'
}

workflow_trigger_has_branches() {
  local trigger="$1"
  awk -v trigger="$trigger:" '$1 == trigger { found = 1; next } found { print; exit }' "$workflow" |
    grep -Fq 'branches: [dev, main]'
}

workflow_pins_actions_to_sha() {
  grep -Eq "$action_pinned_to_sha" "$workflow" || return 1
  ! grep -Eq "$action_pinned_to_name" "$workflow"
}

hook_scans_staged_changes() {
  [ -x .githooks/pre-commit ] || return 1
  file_contains .githooks/pre-commit gitleaks -- --staged
}

hook_setup_script_is_ready() {
  [ -x scripts/setup-hooks.sh ] || return 1
  file_contains scripts/setup-hooks.sh 'core.hooksPath .githooks'
}

hooks_are_activated() {
  [ "$(git config core.hooksPath)" = .githooks ]
}

check "compose file is valid" docker compose config --quiet
check "compose defines workspace and gitleaks services" compose_has_services workspace gitleaks
check "workspace image is pinned by version and digest" file_matches Dockerfile "$node_image_pattern"
check "workspace container runs as a non-root user" file_has_lines Dockerfile 'USER node'
check "gitleaks image is pinned by version and digest" file_matches docker-compose.yml "$gitleaks_image_pattern"
check "gitleaks mounts the repository read-only" file_contains docker-compose.yml '.:/repo:ro'
check "pnpm version is pinned in package.json" file_matches package.json "$pnpm_version_pattern"
check "ci script runs audit, lint, typecheck, test and build in order" file_matches package.json "$ci_gates_pattern"
check "workspace declares apps and packages" file_contains pnpm-workspace.yaml 'apps/*' 'packages/*'
check "base compose has no bind mount, override adds it" bind_mount_only_in_override
check "dockerignore excludes dependencies, git data and secrets" file_has_lines .dockerignore \
  '**/node_modules' .git '**/.env*' '**/.npmrc' '**/*.pem' '**/*.key' '**/dist' '**/coverage'
check "gitignore excludes env files and credentials" file_has_lines .gitignore '.env*' .npmrc '*.pem' '*.key'
check "workflow runs on pull requests to dev and main" workflow_trigger_has_branches pull_request
check "workflow runs on pushes to dev and main" workflow_trigger_has_branches push
check "workflow runner is pinned" file_contains "$workflow" 'runs-on: ubuntu-24.04'
check "workflow cancels superseded runs only on pull requests" file_contains "$workflow" "$cancel_only_on_pull_requests"
check "workflow runs gitleaks and the pipeline through docker compose without the dev override" \
  file_contains "$workflow" \
  'run: docker compose -f docker-compose.yml run --rm gitleaks' \
  'run: docker compose -f docker-compose.yml run --rm workspace pnpm run ci'
check "workflow pins actions to a commit sha" workflow_pins_actions_to_sha
check "workflow requests read-only permissions" file_contains "$workflow" 'contents: read'
check "pre-commit hook scans staged changes for secrets" hook_scans_staged_changes
check "dependabot covers npm, docker, docker-compose and github-actions" file_has_lines .github/dependabot.yml \
  '  - package-ecosystem: npm' \
  '  - package-ecosystem: docker' \
  '  - package-ecosystem: docker-compose' \
  '  - package-ecosystem: github-actions'
check "hook setup script exists and is executable" hook_setup_script_is_ready
check "git hooks are activated (run scripts/setup-hooks.sh)" hooks_are_activated
check "secret scan finds no leaks" docker compose -f docker-compose.yml run --rm gitleaks
check "pipeline command passes inside the workspace container as CI runs it" \
  docker compose -f docker-compose.yml run --rm --build workspace pnpm run ci

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
