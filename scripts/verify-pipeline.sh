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

env_guard_rejects_tracked_env_files() {
  local repo guard scratch result
  repo=$(pwd)
  guard="$repo/scripts/check-env-files.sh"
  scratch=$(mktemp -d) || return 1
  (
    cd "$scratch" || exit 1
    git init -q . && git config user.email guard@example.test && git config user.name guard
    printf 'MODULE_DB_PASSWORD=\n' > .env && git add .env && git commit -q -m "chore: planted"
  ) || { rm -rf "$scratch"; return 1; }
  [ -x "$guard" ] && ! "$guard" "$scratch" >/dev/null 2>&1
  result=$?
  rm -rf "$scratch"
  return "$result"
}

env_guard_accepts_env_example() {
  local repo guard scratch result
  repo=$(pwd)
  guard="$repo/scripts/check-env-files.sh"
  scratch=$(mktemp -d) || return 1
  (
    cd "$scratch" || exit 1
    git init -q . && git config user.email guard@example.test && git config user.name guard
    printf 'MODULE_DB_PASSWORD=\n' > .env.example && git add .env.example && git commit -q -m "chore: example"
  ) || { rm -rf "$scratch"; return 1; }
  [ -x "$guard" ] && "$guard" "$scratch" >/dev/null 2>&1
  result=$?
  rm -rf "$scratch"
  return "$result"
}

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
  local services
  services=$(docker compose config --services)
  grep -qx "$1" <<<"$services"
}

compose_has_tools_service() {
  local services
  services=$(docker compose --profile tools config --services)
  grep -qx "$1" <<<"$services"
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

approved_advisory='GHSA-fc5q-39xc-vjpf'
ghsa_id_pattern='GHSA-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}'

audit_ignores_only_the_approved_advisory() {
  local count
  file_contains pnpm-workspace.yaml "$approved_advisory" || return 1
  count=$(grep -oE "$ghsa_id_pattern" pnpm-workspace.yaml | sort -u | wc -l | tr -d ' ')
  [ "$count" -eq 1 ] || return 1
  [ "$(grep -oE "$ghsa_id_pattern" pnpm-workspace.yaml | sort -u)" = "$approved_advisory" ]
}

audit_exception_is_explained_inline() {
  local context comments
  context=$(grep -B3 -- "$approved_advisory" pnpm-workspace.yaml) || return 1
  comments=$(grep -E '#' <<<"$context" | grep -iw dev | grep -i remove) || return 1
  [ -n "$comments" ]
}

module_db_check_skips_env_sourcing() {
  local script=scripts/check-module-databases.sh
  file_lacks "$script" '. "./$ENV_FILE"' || return 1
  ! grep -Eq '^[[:space:]]*(\.|source)[[:space:]]+.*\.env' "$script" || return 1
  file_contains "$script" MYSQL_PWD
}

module_db_check_keeps_password_off_argv() {
  file_lacks scripts/check-module-databases.sh '-p"$MODULE_DB_PASSWORD"'
}

api_dev_script_has_comments() {
  local script=apps/api/scripts/dev.sh comment_count
  [ -f "$script" ] || return 1
  file_contains "$script" tsc 'node --watch' || return 1
  comment_count=$(grep -v '^#!' "$script" | grep -c '^#' || true)
  [ "$comment_count" -ge 2 ]
}

api_dev_runs_commented_script() {
  file_contains apps/api/package.json '"dev": "sh scripts/dev.sh"' || return 1
  api_dev_script_has_comments
}

makefile_marks_seed_credentials_as_dummies() {
  grep -Eiq '^#.*dummy' Makefile
}

readme_line_has_both() {
  grep -F -- "$1" README.md | grep -F -- "$2" >/dev/null
}

readme_explains_password_change_and_checksum_stop() {
  readme_line_has_both MODULE_DB_PASSWORD 'make down-v' || return 1
  readme_line_has_both checksum stops
}

job_text() {
  awk -v id="$1" '
    $0 == "  " id ":" { found = 1; print; next }
    found && /^  [^ #][^ :]*:/ { exit }
    found { print }
  ' "$workflow"
}

text_contains_all() {
  local text="$1" needle
  shift
  for needle in "$@"; do
    grep -Fq -- "$needle" <<<"$text" || return 1
  done
}

job_needs() {
  local job="$1" needed="$2" text
  text=$(job_text "$job")
  grep -Eq "^ +- +$needed *\$|needs:.*[^a-z_-]$needed([^a-z_-]|\$)" <<<"$text"
}

grant_only_in_job() {
  local grant="$1" job="$2" text
  [ "$(grep -cF -- "$grant" "$workflow")" -eq 1 ] || return 1
  text=$(job_text "$job")
  text_contains_all "$text" "$grant"
}

workflow_permissions_block() {
  awk '/^permissions:/ { found = 1; next } found && /^[^ #]/ { exit } found { print }' "$workflow"
}

workflow_grants_only_read() {
  local block
  block=$(workflow_permissions_block)
  text_contains_all "$block" 'contents: read' || return 1
  ! grep -Eq ':[[:space:]]*write' <<<"$block"
}

packages_write_only_in_publish() {
  grant_only_in_job 'packages: write' publish && workflow_grants_only_read
}

if_line_pattern='^ *(- +)?if:'

publish_runs_on_push_to_main() {
  local text if_line
  text=$(job_text publish)
  if_line=$(grep -E "$if_line_pattern" <<<"$text") || return 1
  text_contains_all "$if_line" 'refs/heads/main' push && job_needs publish image
}

every_job_times_out_at_twenty_minutes() {
  [ "$(grep -Ec '^ +timeout-minutes: 20 *$' "$workflow")" -eq 6 ]
}

workflow_has_six_jobs() {
  local id
  for id in checks integration migration image publish ci; do
    file_matches "$workflow" "^  $id:" || return 1
  done
}

ci_gate_needs_every_job() {
  local job
  for job in checks integration migration image publish; do
    job_needs ci "$job" || return 1
  done
}

ci_gate_checks_results() {
  local text
  text=$(job_text ci)
  text_contains_all "$text" 'if: always()' 'needs.*.result' failure cancelled
}

ci_gate_job_is_ready() {
  ci_gate_needs_every_job && ci_gate_checks_results
}

image_job_builds_and_caches_sha_image() {
  local text
  text=$(job_text image)
  text_contains_all "$text" docker/build-push-action 'cache-from: type=gha' 'cache-to: type=gha' 'sha-'
}

image_job_scans_with_trivy() {
  local text
  text=$(job_text image)
  text_contains_all "$text" aquasecurity/trivy-action 'ignore-unfixed: true' 'HIGH,CRITICAL' "exit-code: '1'" upload-sarif
}

sarif_upload_skips_fork_pull_requests() {
  local text if_lines
  text=$(job_text image)
  if_lines=$(grep -E "$if_line_pattern" <<<"$text") || return 1
  text_contains_all "$if_lines" github.repository github.event.pull_request.head.repo.full_name
}

unit_tests_write_uploaded_junit_report() {
  file_contains "$workflow" upload-artifact junit
}

jobs_run_their_test_suites() {
  local text
  text=$(job_text checks)
  text_contains_all "$text" 'pnpm run test:unit' || return 1
  text=$(job_text integration)
  text_contains_all "$text" 'pnpm run test:integration' || return 1
  text=$(job_text migration)
  text_contains_all "$text" scripts/migration-dry-run.sh
}

two_attempts_pattern='for [A-Za-z_]+ in 1 2( |;|$)|seq 1 2|ATTEMPTS=2|attempts=2'

image_pulls_retry_with_warning() {
  file_contains "$workflow" scripts/ci-pull.sh || return 1
  [ -x scripts/ci-pull.sh ] || return 1
  file_contains scripts/ci-pull.sh 'docker compose' pull '::warning::' || return 1
  file_matches scripts/ci-pull.sh "$two_attempts_pattern"
}

test_suites_are_split() {
  file_contains package.json '"test:unit"' '"test:integration"' || return 1
  file_contains apps/api/package.json '"test:unit"' '"test:integration"'
}

migration_dry_run_passes() {
  [ -x scripts/migration-dry-run.sh ] && scripts/migration-dry-run.sh
}

api_stage_pattern='^FROM node:24\.22\.3-alpine@sha256:[0-9a-f]{64} AS api$'

dockerfile_has_production_api_stage() {
  local api_line user_line
  api_line=$(grep -nE "$api_stage_pattern" Dockerfile | cut -d: -f1) || return 1
  user_line=$(grep -nxF 'USER node' Dockerfile | tail -n 1 | cut -d: -f1) || return 1
  [ "$user_line" -gt "$api_line" ] || return 1
  file_matches Dockerfile '^CMD \["node", ?"dist/index\.js"\]'
}

api_container=sonora-api-verify

remove_api_container() {
  docker rm -f "$api_container" >/dev/null 2>&1 || true
}

build_api_image() {
  docker build --target api -t sonora-api:verify . >/dev/null 2>&1
}

start_api_container() {
  docker run -d --name "$api_container" sonora-api:verify >/dev/null 2>&1
}

api_health_body() {
  docker exec "$api_container" wget -q -O - http://127.0.0.1:3000/health 2>/dev/null || true
}

api_is_healthy() {
  [ "$(api_health_body)" = '{"status":"ok"}' ]
}

wait_for_api_health() {
  local attempt
  for attempt in $(seq 1 60); do
    api_is_healthy && return 0
    sleep 1
  done
  return 1
}

api_image_answers_health() {
  local verdict=1
  remove_api_container
  if build_api_image && start_api_container && wait_for_api_health; then
    verdict=0
  fi
  remove_api_container
  return "$verdict"
}

compose_run_lines() {
  grep -F 'docker compose -f docker-compose.yml run' "$workflow"
}

workflow_runs_script_via_compose() {
  local lines
  lines=$(compose_run_lines) || return 1
  grep -Eq "pnpm run $1( |\$)" <<<"$lines"
}

workflow_runs_gate_scripts_via_compose() {
  local script
  for script in audit:dependencies lint check:boundaries typecheck test:unit test:integration build; do
    workflow_runs_script_via_compose "$script" || return 1
  done
}

gitleaks_and_gates_run_via_compose() {
  file_contains "$workflow" 'run: docker compose -f docker-compose.yml run --rm gitleaks' || return 1
  workflow_runs_gate_scripts_via_compose
}

compose_lines_without_base_file() {
  grep -F 'docker compose' "$workflow" | grep -Fv -- '-f docker-compose.yml'
}

workflow_never_uses_dev_override() {
  file_lacks "$workflow" docker-compose.override.yml || return 1
  [ -z "$(compose_lines_without_base_file)" ]
}

publish_waits_for_every_gate() {
  local job
  for job in checks integration migration image; do
    job_needs publish "$job" || return 1
  done
}

trivy_limits_sarif_severities() {
  text_contains_all "$(job_text image)" 'limit-severities-for-sarif: true'
}

upload_sarif_skips_dependabot_and_missing_report() {
  local text if_lines
  text=$(job_text image)
  if_lines=$(grep -E "$if_line_pattern" <<<"$text") || return 1
  text_contains_all "$if_lines" 'dependabot[bot]' "hashFiles('trivy.sarif')"
}

migration_dry_run_uses_base_compose_file() {
  local script=scripts/migration-dry-run.sh compose_lines
  compose_lines=$(grep 'docker compose' "$script") || return 1
  text_contains_all "$compose_lines" '-f docker-compose.yml' || return 1
  file_lacks "$script" docker-compose.override.yml
}

package_test_script_is_split() {
  local file="$1"
  grep -q '"test":' "$file" || return 0
  grep -Eq '"test:(unit|integration)":' "$file"
}

packages_with_tests_run_in_ci() {
  local file
  while IFS= read -r file; do
    package_test_script_is_split "$file" || return 1
  done < <(find apps packages modules infra -name package.json -not -path '*/node_modules/*')
}

api_stage_text() {
  awk '/ AS api$/ { found = 1 } found { print }' Dockerfile
}

api_stage_removes_npm() {
  local text
  text=$(api_stage_text)
  text_contains_all "$text" 'rm -rf /usr/local/lib/node_modules/npm' /usr/local/bin/npm /usr/local/bin/npx
}

api_image_exists() {
  docker image inspect sonora-api:verify >/dev/null 2>&1
}

ensure_api_image() {
  api_image_exists || build_api_image
}

api_image_has_no_npm() {
  ensure_api_image || return 1
  docker run --rm --entrypoint sh sonora-api:verify \
    -c 'test ! -e /usr/local/lib/node_modules/npm && ! command -v npm && ! command -v npx' >/dev/null 2>&1 || return 1
  docker run --rm --entrypoint node sonora-api:verify --version >/dev/null 2>&1
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
  'run: docker compose -f docker-compose.yml run --rm --no-deps workspace pnpm run check:boundaries'
check "workspace declares apps and packages" file_contains pnpm-workspace.yaml 'apps/*' 'packages/*'
check "base compose has no bind mount, override adds it" bind_mount_only_in_override
check "dockerignore excludes dependencies, git data and secrets" file_has_lines .dockerignore \
  '**/node_modules' .git '**/.env*' '**/.npmrc' '**/*.pem' '**/*.key' '**/dist' '**/coverage'
check "gitignore excludes env files and credentials" file_has_lines .gitignore '.env*' .npmrc '*.pem' '*.key'
check "workflow runs on pull requests to dev and main" workflow_trigger_has_branches pull_request
check "workflow runs on pushes to dev and main" workflow_trigger_has_branches push
check "workflow runner is pinned" file_contains "$workflow" 'runs-on: ubuntu-24.04'
check "workflow cancels superseded runs only on pull requests" file_contains "$workflow" "$cancel_only_on_pull_requests"
check "workflow runs gitleaks and each gate script (audit, lint, boundaries, typecheck, unit, integration, build) through docker compose -f docker-compose.yml" \
  gitleaks_and_gates_run_via_compose
check "the workflow never uses the dev override file" workflow_never_uses_dev_override
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
check "the pnpm audit ignores exactly one approved advisory" audit_ignores_only_the_approved_advisory
check "the advisory exception is explained next to it" audit_exception_is_explained_inline
check "the audit passes with the exception" docker compose run --rm --no-deps workspace pnpm audit --audit-level=high
check "the module database check does not source .env" module_db_check_skips_env_sourcing
check "the module database check does not put the password on the command line" module_db_check_keeps_password_off_argv
check "the api dev script calls a small commented script" api_dev_runs_commented_script
check "the Makefile marks the seed credentials as dummies" makefile_marks_seed_credentials_as_dummies
check "the README explains password changes and the checksum stop" readme_explains_password_change_and_checksum_stop
check "ci has the six jobs" workflow_has_six_jobs
check "the ci gate job needs every other job and fails on failure or cancellation" ci_gate_job_is_ready
check "packages write is granted only to the publish job" packages_write_only_in_publish
check "security-events write is granted only to the image job" grant_only_in_job 'security-events: write' image
check "publish runs only on a push to main" publish_runs_on_push_to_main
check "publish waits for every gate job" publish_waits_for_every_gate
check "trivy limits severities when it writes SARIF" trivy_limits_sarif_severities
check "the SARIF upload skips Dependabot runs and a missing report" upload_sarif_skips_dependabot_and_missing_report
check "the migration dry run uses only the base compose file" migration_dry_run_uses_base_compose_file
check "the workflow never continues on error" file_lacks "$workflow" continue-on-error
check "a tracked .env file other than .env.example is rejected" env_guard_rejects_tracked_env_files
check "the .env.example file is accepted" env_guard_accepts_env_example
check "pull requests check the API contract against the base branch" file_contains "$workflow" "scripts/contracts-check.sh"
check "every package that has a test script also has a test script that CI runs" packages_with_tests_run_in_ci
check "the api stage removes npm from the production image" api_stage_removes_npm
check "the built api image has no npm" api_image_has_no_npm
check "every job has a 20 minute timeout" every_job_times_out_at_twenty_minutes
check "the image job builds once with buildx and the GitHub cache, tagged sha-" image_job_builds_and_caches_sha_image
check "trivy fails on fixable high and critical findings and uploads SARIF" image_job_scans_with_trivy
check "SARIF upload is skipped for fork pull requests" sarif_upload_skips_fork_pull_requests
check "unit tests write a JUnit report that is uploaded" unit_tests_write_uploaded_junit_report
check "the checks job runs the unit tests and the integration job runs the integration tests" jobs_run_their_test_suites
check "image pulls are retried with a warning" image_pulls_retry_with_warning
check "the root and the api package split unit and integration tests" test_suites_are_split
check "unit tests run without a database" timeout 600 docker compose run --rm --no-deps workspace pnpm run test:unit
check "the migration dry run applies the migrations and a second run is a no-op" migration_dry_run_passes
check "the Dockerfile has a production api stage" dockerfile_has_production_api_stage
check "the production api image starts and answers /health" api_image_answers_health

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
