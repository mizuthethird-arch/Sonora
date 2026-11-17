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

compose_has_default_service() {
  docker compose config --services | grep -qx "$1"
}

compose_has_tools_service() {
  docker compose --profile tools config --services | grep -qx "$1"
}

compose_has_workspace_and_gitleaks() {
  compose_has_default_service workspace || return 1
  compose_has_tools_service gitleaks
}

bind_mount_only_in_override() {
  file_lacks docker-compose.yml '.:/workspace' || return 1
  file_contains docker-compose.override.yml '.:/workspace'
}

line_after() {
  local file="$1"
  local line_start="$2"
  awk -v wanted="$line_start" '$1 == wanted { found = 1; next } found { print; exit }' "$file"
}

workflow_trigger_has_branches() {
  local trigger="$1"
  line_after "$workflow" "$trigger:" | grep -Fq 'branches: [dev, main]'
}

workflow_pins_actions_to_sha() {
  grep -Eq "$action_pinned_to_sha" "$workflow" || return 1
  ! grep -Eq "$action_pinned_to_name" "$workflow"
}

hook_scans_staged_changes() {
  [ -x .githooks/pre-commit ] || return 1
  file_contains .githooks/pre-commit gitleaks '--staged'
}

commit_msg_hook_runs_commitlint() {
  [ -x .githooks/commit-msg ] || return 1
  file_contains .githooks/commit-msg 'pnpm run' 'commitlint' || return 1
  file_matches package.json '"commitlint": ".*@sonora/config exec commitlint --config commitlint.config.js"'
}

commit_msg_hook_judges_messages() {
  local bad_message good_message verdict=0
  bad_message=$(mktemp)
  good_message=$(mktemp)
  printf 'fixed stuff\n' >"$bad_message"
  printf 'fix(api): return 404 for unknown track\n' >"$good_message"

  .githooks/commit-msg "$bad_message" >/dev/null 2>&1 && verdict=1
  .githooks/commit-msg "$good_message" >/dev/null 2>&1 || verdict=1

  rm -f "$bad_message" "$good_message"
  return "$verdict"
}

workflow_checks_the_pr_title_through_the_environment() {
  file_contains "$workflow" \
    "PR_TITLE: \${{ github.event.pull_request.title }}" \
    'printf '"'"'%s\n'"'"' "$PR_TITLE" | docker compose -f docker-compose.yml run --rm --no-deps -T workspace pnpm run --silent commitlint'
}

hook_setup_script_is_ready() {
  [ -x scripts/setup-hooks.sh ] || return 1
  file_contains scripts/setup-hooks.sh 'core.hooksPath .githooks'
}

hooks_are_activated() {
  [ "$(git config core.hooksPath)" = .githooks ]
}

compose_defines_development_services() {
  local service
  for service in mysql redis s3 mailpit traefik api media-worker; do
    compose_has_default_service "$service" || return 1
  done
}

image_line_pinned_by_digest() {
  file_matches docker-compose.yml "image: .*$1.*@sha256:[0-9a-f]{64}"
}

dev_service_images_pinned_by_digest() {
  image_line_pinned_by_digest redis || return 1
  image_line_pinned_by_digest adobe/s3mock || return 1
  image_line_pinned_by_digest axllent/mailpit || return 1
  image_line_pinned_by_digest traefik || return 1
  file_matches infra/media-worker/Dockerfile '^FROM node:24-trixie-slim@sha256:[0-9a-f]{64}'
}

only_traefik_publishes_a_port() {
  [ "$(docker compose config | grep -c 'published:')" -eq 1 ]
}

mysql_init_creates_module_databases() {
  file_contains infra/mysql/init/01-module-databases.sh \
    identity catalog media playback library search recommender realtime notification analytics platform
}

media_worker_runs_and_installs_ffmpeg() {
  file_contains docker-compose.yml ffmpeg -version || return 1
  file_contains infra/media-worker/Dockerfile 'apt-get install' ffmpeg
}

makefile_has_development_targets() {
  local target
  for target in up down down-v seed migrate test logs doctor check-databases env-check; do
    grep -Eq "^${target}:" Makefile || return 1
  done
}

env_file_is_rejected() {
  local output
  output=$(./scripts/check-env.sh "$1" 2>&1) && return 1
  [ -n "$output" ]
}

env_file_rejected_naming_key() {
  local output
  output=$(./scripts/check-env.sh "$1" 2>&1) && return 1
  grep -Fq MODULE_DB_PASSWORD <<<"$output"
}

env_file_accepted_without_echoing_value() {
  local output
  output=$(./scripts/check-env.sh "$1" 2>&1) || return 1
  ! grep -Fq dev-only <<<"$output"
}

check_env_rejects_bad_files() {
  local empty filled missing verdict=0
  empty=$(mktemp)
  filled=$(mktemp)
  missing="$filled.missing"
  printf 'MODULE_DB_PASSWORD=\n' >"$empty"
  printf 'MODULE_DB_PASSWORD=dev-only\n' >"$filled"

  env_file_is_rejected "$missing" || verdict=1
  env_file_rejected_naming_key "$empty" || verdict=1
  env_file_accepted_without_echoing_value "$filled" || verdict=1

  rm -f "$empty" "$filled"
  return "$verdict"
}

make_up_stops_on_empty_key() {
  local env_file output verdict=0
  env_file=$(mktemp)
  printf 'MODULE_DB_PASSWORD=\n' >"$env_file"
  output=$(timeout 20 make up ENV_FILE="$env_file" 2>&1) && verdict=1
  rm -f "$env_file"
  [ "$verdict" -eq 0 ] && grep -Fq MODULE_DB_PASSWORD <<<"$output"
}

check "compose file is valid" docker compose config --quiet
check "compose defines workspace and gitleaks services" compose_has_workspace_and_gitleaks
check "workspace image is pinned by version and digest" file_matches Dockerfile "$node_image_pattern"
check "workspace container runs as a non-root user" file_has_lines Dockerfile 'USER node'
check "gitleaks image is pinned by version and digest" file_matches docker-compose.yml "$gitleaks_image_pattern"
check "gitleaks mounts the repository read-only" file_contains docker-compose.yml '.:/repo:ro'
check "pnpm version is pinned in package.json" file_matches package.json "$pnpm_version_pattern"
check "ci script runs audit, lint, typecheck, test and build in order" file_matches package.json "$ci_gates_pattern"
check "check:boundaries runs dependency-cruiser with the boundaries config" file_matches package.json \
  '"check:boundaries": "depcruise .* --config packages/config/boundaries.cjs'
check "ci runs the boundary check before the tests" file_matches package.json '"ci": ".*check:boundaries.*run test'
check "workflow runs the boundary check as its own step" file_contains "$workflow" \
  'run: docker compose -f docker-compose.yml run --rm workspace pnpm run check:boundaries'
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
check "commit-msg hook checks the message with the shared commitlint config" commit_msg_hook_runs_commitlint
check "commit-msg hook rejects fixed stuff and accepts a conventional message" commit_msg_hook_judges_messages
check "workflow lints the pull request title with commitlint, passed through the environment" \
  workflow_checks_the_pr_title_through_the_environment
check "no release-age exemptions in the pnpm workspace" file_lacks pnpm-workspace.yaml minimumReleaseAgeExclude
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
check "compose defines the development services" compose_defines_development_services
check "development service images are pinned by digest" dev_service_images_pinned_by_digest
check "only traefik publishes a host port" only_traefik_publishes_a_port
check "mysql init creates one database and user per module" mysql_init_creates_module_databases
check "traefik routes the three hostnames" file_contains infra/traefik/dynamic.yml \
  api.sonora.localhost mail.sonora.localhost s3.sonora.localhost
check "media-worker healthcheck runs ffmpeg -version and the image installs ffmpeg" media_worker_runs_and_installs_ffmpeg
check "Makefile has the development targets" makefile_has_development_targets
check ".env.example exists with the required key empty" file_has_lines .env.example 'MODULE_DB_PASSWORD='
check "check-env rejects a missing file, an empty required key, and accepts a filled one" check_env_rejects_bad_files
check "make up stops on an empty required key" make_up_stops_on_empty_key
check "api has a dev script for hot reload" file_contains apps/api/package.json '"dev":'

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
