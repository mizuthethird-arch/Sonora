#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

failures=0
workflow=".github/workflows/ci.yml"
dependabot=".github/dependabot.yml"

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

# Prints the meilisearch service block of docker-compose.yml (from its key up to the next service or top-level key).
meilisearch_service_block() {
  awk '$0 == "  meilisearch:" { found = 1; next } found && (/^[^ ]/ || /^  [^ ]/) { exit } found { print }' docker-compose.yml
}

meilisearch_image_is_pinned() {
  meilisearch_service_block | grep -Fqx -- '    image: getmeili/meilisearch:v1.56.0@sha256:1f578fa865f8251894b3bf38d6668d6209a3f451f8f65ab953e129d4c1db5ef4'
}

meilisearch_has_healthcheck() {
  meilisearch_service_block | grep -Fq 'healthcheck:'
}

meilisearch_publishes_no_port() {
  local block
  block=$(meilisearch_service_block)
  [ -n "$block" ] || return 1
  ! grep -Eq '^[[:space:]]+ports:' <<<"$block"
}

meilisearch_master_key_comes_from_env_in_production_mode() {
  local block
  block=$(meilisearch_service_block)
  grep -Fq 'MEILI_MASTER_KEY: ${MEILI_MASTER_KEY:-}' <<<"$block" || return 1
  grep -Eq 'MEILI_ENV: "?production"?' <<<"$block"
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

env_file_rejected_naming_meili_key() {
  local output
  output=$(./scripts/check-env.sh "$1" 2>&1) && return 1
  grep -Fq MEILI_MASTER_KEY <<<"$output"
}

env_file_accepted_without_echoing_value() {
  local output
  output=$(./scripts/check-env.sh "$1" 2>&1) || return 1
  ! grep -Fq dev-only <<<"$output"
}

# Writes a file with MODULE_DB_PASSWORD set and MEILI_MASTER_KEY=$2. printf '%s' keeps $, # and quotes literal.
write_env_file() {
  printf '%s\n' "MODULE_DB_PASSWORD=dev-only" "MEILI_MASTER_KEY=$2" >"$1"
}

env_file_rejected_naming_meili_key_without_value() {
  local output
  output=$(./scripts/check-env.sh "$1" 2>&1) && return 1
  grep -Fq MEILI_MASTER_KEY <<<"$output" && ! grep -Fq -- "$2" <<<"$output"
}

env_file_accepted_without_echoing_meili_key() {
  local output
  output=$(./scripts/check-env.sh "$1" 2>&1) || return 1
  ! grep -Fq -- "$2" <<<"$output"
}

check_env_rejects_bad_files() {
  local empty filled meili_empty missing verdict=0
  local meili_short meili_dollar meili_hash meili_dquote meili_squote meili_exact16
  empty=$(mktemp)
  filled=$(mktemp)
  meili_empty=$(mktemp)
  meili_short=$(mktemp)
  meili_dollar=$(mktemp)
  meili_hash=$(mktemp)
  meili_dquote=$(mktemp)
  meili_squote=$(mktemp)
  meili_exact16=$(mktemp)
  missing="$filled.missing"
  printf 'MODULE_DB_PASSWORD=\n' >"$empty"
  printf 'MODULE_DB_PASSWORD=dev-only\nMEILI_MASTER_KEY=dev-meili-master-key-0123\n' >"$filled"
  printf 'MODULE_DB_PASSWORD=dev-only\nMEILI_MASTER_KEY=\n' >"$meili_empty"
  write_env_file "$meili_short" 'short'
  write_env_file "$meili_dollar" 'abcdefgh$ijklmnopqrs'
  write_env_file "$meili_hash" 'abcdefghijklmnop#comment-not-a-comment-xx'
  write_env_file "$meili_dquote" 'abcdefgh"ijklmnopqrstu'
  write_env_file "$meili_squote" "abcdefgh'ijklmnopqrstu"
  write_env_file "$meili_exact16" 'abcdefghijklmnop'

  env_file_is_rejected "$missing" || verdict=1
  env_file_rejected_naming_key "$empty" || verdict=1
  env_file_rejected_naming_meili_key "$meili_empty" || verdict=1
  env_file_accepted_without_echoing_value "$filled" || verdict=1
  env_file_rejected_naming_meili_key_without_value "$meili_short" 'short' || verdict=1
  env_file_rejected_naming_meili_key_without_value "$meili_dollar" 'abcdefgh$ijklmnopqrs' || verdict=1
  env_file_rejected_naming_meili_key_without_value "$meili_hash" 'abcdefghijklmnop#comment-not-a-comment-xx' || verdict=1
  env_file_rejected_naming_meili_key_without_value "$meili_dquote" 'abcdefgh"ijklmnopqrstu' || verdict=1
  env_file_rejected_naming_meili_key_without_value "$meili_squote" "abcdefgh'ijklmnopqrstu" || verdict=1
  env_file_accepted_without_echoing_meili_key "$meili_exact16" 'abcdefghijklmnop' || verdict=1

  rm -f "$empty" "$filled" "$meili_empty" "$meili_short" "$meili_dollar" "$meili_hash" \
    "$meili_dquote" "$meili_squote" "$meili_exact16"
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

makefile_up_starts_meilisearch() {
  line_after Makefile up: | grep -Eq 'docker compose up .*[[:space:]]meilisearch([[:space:]]|$)'
}

doctor_lists_meilisearch() {
  file_matches scripts/doctor.sh '^SERVICES=\(.*meilisearch.*\)'
}

readme_services_table_lists_meilisearch() {
  grep -Eq '^\| meilisearch \|' README.md
}

readme_up_and_doctor_rows_name_meilisearch() {
  readme_line_has_both '`make up`' meilisearch || return 1
  readme_line_has_both '`make doctor`' meilisearch
}

readme_env_table_requires_meili_master_key() {
  grep -Eq '^\| `MEILI_MASTER_KEY` \| Yes \|.*16 characters' README.md
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
  [ "$(grep -Ec '^ +timeout-minutes: 20 *$' "$workflow")" -eq 7 ]
}

workflow_has_seven_jobs() {
  local id
  for id in checks integration migration image publish ci automerge; do
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

dependabot_ecosystem_text() {
  awk -v ecosystem="$1" '
    $0 == "  - package-ecosystem: " ecosystem { found = 1; print; next }
    found && /^  - / { exit }
    found { print }
  ' "$dependabot"
}

dependabot_groups_cover_stack() {
  local npm_text docker_text group
  npm_text=$(dependabot_ecosystem_text npm)
  docker_text=$(dependabot_ecosystem_text docker)
  for group in react vite testing lint; do
    text_contains_all "$npm_text" "      $group:" || return 1
  done
  text_contains_all "$docker_text" '      docker-base-images:'
}

dependabot_every_interval_is_weekly() {
  local intervals
  intervals=$(grep -E '^[[:space:]]*interval:' "$dependabot") || return 1
  ! grep -Evq '^[[:space:]]*interval: weekly[[:space:]]*$' <<<"$intervals"
}

dependabot_updates_weekly_and_cover_ecosystems() {
  dependabot_every_interval_is_weekly || return 1
  file_has_lines "$dependabot" \
    '  - package-ecosystem: npm' \
    '  - package-ecosystem: docker' \
    '  - package-ecosystem: github-actions' \
    '  - package-ecosystem: docker-compose'
}

dependabot_skips_modules_directory() {
  ! file_matches "$dependabot" '(directory|directories):[[:space:]]*"?\.?/?modules|^[[:space:]]+- +"?\.?/?modules'
}

dependabot_major_updates_are_not_grouped() {
  local npm_text docker_text
  npm_text=$(dependabot_ecosystem_text npm)
  docker_text=$(dependabot_ecosystem_text docker)
  text_contains_all "$npm_text" 'update-types:' || return 1
  text_contains_all "$docker_text" 'update-types:' || return 1
  ! grep -Fq major <<<"$npm_text" && ! grep -Fq major <<<"$docker_text"
}

ci_has_automerge_job() {
  local text if_lines
  text=$(job_text automerge)
  [ -n "$text" ] || return 1
  if_lines=$(grep -E "$if_line_pattern" <<<"$text") || return 1
  text_contains_all "$if_lines" \
    "github.actor == 'dependabot[bot]'" \
    "github.event_name == 'pull_request'" \
    "update-type == 'version-update:semver-patch'" \
    "dependency-type == 'direct:development'" || return 1
  text_contains_all "$text" 'gh pr merge' || return 1
  grep -Eq 'uses: dependabot/fetch-metadata@[0-9a-f]{40}' <<<"$text" || return 1
  job_needs automerge ci
}

ci_gate_does_not_need_automerge() {
  ! job_needs ci automerge
}

automerge_checks_every_updated_dependency() {
  text_contains_all "$(job_text automerge)" \
    'updated-dependencies-json' 'jq' 'dependencyType' 'updateType'
}

automerge_merge_pins_head_commit() {
  text_contains_all "$(job_text automerge)" '--match-head-commit'
}

automerge_requires_pr_author() {
  local text if_lines
  text=$(job_text automerge)
  if_lines=$(grep -E "$if_line_pattern" <<<"$text") || return 1
  text_contains_all "$if_lines" "github.event.pull_request.user.login == 'dependabot[bot]'"
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
check "dependabot groups react, vite, testing and lint for npm and docker-base-images for docker" dependabot_groups_cover_stack
check "dependabot updates weekly and covers npm, docker, github-actions and docker-compose" dependabot_updates_weekly_and_cover_ecosystems
check "dependabot skips the modules directory" dependabot_skips_modules_directory
check "dependabot npm and docker groups use update-types and never group major updates" dependabot_major_updates_are_not_grouped
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
check "check-env rejects a missing file, an empty required key, a MEILI_MASTER_KEY under 16 characters or containing \$, # or quotes, and accepts a filled key and one of exactly 16 characters" check_env_rejects_bad_files
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
check "ci has the seven jobs" workflow_has_seven_jobs
check "the ci gate job needs every other job and fails on failure or cancellation" ci_gate_job_is_ready
check "the ci gate job does not need the automerge job, which needs the gate" ci_gate_does_not_need_automerge
check "ci has an automerge job for Dependabot patch dev-dependency updates, after ci" ci_has_automerge_job
check "automerge checks every updated dependency in the Dependabot metadata, not only the PR-level output" automerge_checks_every_updated_dependency
check "automerge merge pins the head commit with --match-head-commit" automerge_merge_pins_head_commit
check "automerge job-level if requires the Dependabot PR author" automerge_requires_pr_author
check "contents write is granted only to the automerge job" grant_only_in_job 'contents: write' automerge
check "pull-requests write is granted only to the automerge job" grant_only_in_job 'pull-requests: write' automerge
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
check "compose defines the meilisearch service" compose_has_default_service meilisearch
check "meilisearch image is pinned by version and digest" meilisearch_image_is_pinned
check "meilisearch has a healthcheck" meilisearch_has_healthcheck
check "meilisearch publishes no host port" meilisearch_publishes_no_port
check "meilisearch reads its master key from the environment and runs in production mode, which refuses an empty key" meilisearch_master_key_comes_from_env_in_production_mode
check ".env.example lists MEILI_MASTER_KEY empty" file_has_lines .env.example 'MEILI_MASTER_KEY='
check "doctor checks meilisearch" doctor_lists_meilisearch
check "make up starts meilisearch" makefile_up_starts_meilisearch
check "README services table lists meilisearch" readme_services_table_lists_meilisearch
check "README make up and make doctor rows name meilisearch" readme_up_and_doctor_rows_name_meilisearch
check "README env table marks MEILI_MASTER_KEY required, at least 16 characters" readme_env_table_requires_meili_master_key

deploy_workflow=".github/workflows/deploy.yml"
staging_workflow=".github/workflows/staging.yml"
production_workflow=".github/workflows/production.yml"
deploy_runbook="docs/deploy-runbook.md"
deploy_secret_pattern='\$\{\{ *secrets\.[A-Z0-9_]+ *\}\}'

every_action_pinned_to_sha() {
  [ -f "$1" ] || return 1
  ! grep -F 'uses:' "$1" | grep -Evq "$action_pinned_to_sha"
}

deploy_workflow_triggers_on_workflow_call() {
  [ -f "$deploy_workflow" ] || return 1
  file_matches "$deploy_workflow" '^on: +workflow_call *$' && return 0
  file_has_lines "$deploy_workflow" 'on:' && file_matches "$deploy_workflow" '^  workflow_call:'
}

deploy_workflow_grants_only_read() {
  [ -f "$deploy_workflow" ] || return 1
  file_matches "$deploy_workflow" '^permissions:' || return 1
  file_matches "$deploy_workflow" '^ +contents: read *$' || return 1
  ! grep -Eq ':[[:space:]]*write' "$deploy_workflow"
}

deploy_concurrency_group_has_environment() {
  file_matches "$deploy_workflow" '^concurrency:' &&
    file_matches "$deploy_workflow" 'group: .*inputs\.environment'
}

deploy_jobs_time_out_at_twenty_minutes() {
  local runs timed
  [ -f "$deploy_workflow" ] || return 1
  runs=$(grep -Ec '^    runs-on:' "$deploy_workflow") || true
  timed=$(grep -Ec '^    timeout-minutes: 20 *$' "$deploy_workflow") || true
  [ "$runs" -ge 1 ] && [ "$runs" -eq "$timed" ]
}

deploy_job_uses_environment_input() {
  file_matches "$deploy_workflow" '^ +environment: *\$\{\{ *inputs\.environment *\}\}'
}

deploy_ssh_key_comes_from_secret_env() {
  file_matches "$deploy_workflow" "^ +[A-Z_]*KEY[A-Z_]*: +$deploy_secret_pattern"
}

deploy_known_hosts_comes_from_secret_env() {
  file_matches "$deploy_workflow" "^ +[A-Z_]*KNOWN_HOSTS[A-Z_]*: +$deploy_secret_pattern"
}

deploy_secrets_only_as_env_values() {
  [ -f "$deploy_workflow" ] || return 1
  ! grep -E '\$\{\{ *secrets\.' "$deploy_workflow" |
    grep -Ev "^ *[A-Za-z_-]+: +$deploy_secret_pattern\$" | grep -q .
}

deploy_ssh_is_strict_host_checking() {
  file_contains "$deploy_workflow" 'ssh ' '-o StrictHostKeyChecking=yes'
}

staging_triggers_on_successful_ci_for_main() {
  file_matches "$staging_workflow" '^ +workflow_run:' &&
    file_matches "$staging_workflow" 'workflows: *\[ *"?ci"? *\]|^ +- *"?ci"? *$' &&
    file_matches "$staging_workflow" 'types: *\[ *"?completed"? *\]|^ +- *"?completed"? *$' &&
    file_matches "$staging_workflow" 'branches: *\[ *"?main"? *\]|^ +- *"?main"? *$' &&
    file_contains "$staging_workflow" "github.event.workflow_run.conclusion == 'success'"
}

staging_calls_deploy_for_staging() {
  file_contains "$staging_workflow" './.github/workflows/deploy.yml' &&
    file_matches "$staging_workflow" '^ +environment: *"?staging"? *$'
}

production_triggers_on_version_tags() {
  file_matches "$production_workflow" '^ +push:' &&
    file_contains "$production_workflow" 'tags:' 'v*.*.*'
}

production_calls_deploy_for_production() {
  file_contains "$production_workflow" './.github/workflows/deploy.yml' &&
    file_matches "$production_workflow" '^ +environment: *"?production"? *$'
}

check "deploy script tests pass (bash infra/deploy/tests/run.sh)" bash infra/deploy/tests/run.sh
check "deploy workflow is reusable: on workflow_call" deploy_workflow_triggers_on_workflow_call
check "deploy workflow permissions grant contents read and nothing written" deploy_workflow_grants_only_read
check "deploy workflow concurrency group includes the environment input" deploy_concurrency_group_has_environment
check "deploy workflow jobs time out at twenty minutes" deploy_jobs_time_out_at_twenty_minutes
check "deploy workflow job uses the environment input, so production gets its approval" deploy_job_uses_environment_input
check "deploy workflow ssh key comes from a secret through env" deploy_ssh_key_comes_from_secret_env
check "deploy workflow known_hosts comes from a secret through env" deploy_known_hosts_comes_from_secret_env
check "deploy workflow never puts a secret inside a run line" deploy_secrets_only_as_env_values
check "deploy workflow ssh uses StrictHostKeyChecking=yes" deploy_ssh_is_strict_host_checking
check "deploy workflow pins every action to a 40-hex sha" every_action_pinned_to_sha "$deploy_workflow"
check "staging workflow triggers on completed ci runs on main with conclusion success" staging_triggers_on_successful_ci_for_main
check "staging workflow calls deploy.yml with environment staging" staging_calls_deploy_for_staging
check "staging workflow is guarded by vars.STAGING_DEPLOY_ENABLED" file_contains "$staging_workflow" "vars.STAGING_DEPLOY_ENABLED == 'true'"
check "production workflow triggers on version tags v*.*.*" production_triggers_on_version_tags
check "production workflow calls deploy.yml with environment production" production_calls_deploy_for_production
check "production workflow is guarded by vars.PRODUCTION_DEPLOY_ENABLED" file_contains "$production_workflow" "vars.PRODUCTION_DEPLOY_ENABLED == 'true'"
check "deploy runbook documents the forced command line with command=" file_contains "$deploy_runbook" 'command='
check "deploy runbook documents the forced command restrict option" file_matches "$deploy_runbook" 'restrict([ ,`]|$)'
check "deploy runbook documents the rollback command" file_contains "$deploy_runbook" 'deploy rollback staging' 'deploy rollback production'
check "deploy runbook has a rollback timing table row with the [not timed] placeholder" file_matches "$deploy_runbook" '^\|.*\[not timed\].*\|$'

actionlint_image='rhysd/actionlint:1.7.7@sha256:887a259a5a534f3c4f36cb02dca341673c6089431057242cdc931e9f133147e9'

all_exist() {
  local file
  for file in "$@"; do
    [ -f "$file" ] || return 1
  done
}

# workflow_job_text FILE JOB: the text of JOB in FILE, for any workflow file (job_text reads $workflow only).
workflow_job_text() {
  awk -v id="$2" '
    $0 == "  " id ":" { found = 1; print; next }
    found && /^  [^ #][^ :]*:/ { exit }
    found { print }
  ' "$1"
}

# workflow_job_needs FILE JOB NEEDED: JOB lists NEEDED under its needs key.
workflow_job_needs() {
  local text
  text=$(workflow_job_text "$1" "$2")
  grep -Eq "^ +- +$3 *\$|needs:.*[^a-z_-]$3([^a-z_-]|\$)" <<<"$text"
}

workflows_avoid_substring() {
  all_exist "$deploy_workflow" "$staging_workflow" "$production_workflow" || return 1
  ! grep -Fq 'substring(' "$deploy_workflow" "$staging_workflow" "$production_workflow"
}

actionlint_passes_on_workflows() {
  docker run --rm -v "$PWD:/repo" -w /repo "$actionlint_image" -no-color .github/workflows/*.yml
}

workflows_do_not_inherit_secrets() {
  all_exist "$staging_workflow" "$production_workflow" || return 1
  ! grep -Eq 'secrets:[[:space:]]*inherit' "$staging_workflow" "$production_workflow"
}

staging_deploy_is_gated_on_push_from_this_repo() {
  local if_lines
  all_exist "$staging_workflow" || return 1
  if_lines=$(grep -E "$if_line_pattern" "$staging_workflow") || return 1
  text_contains_all "$if_lines" "github.event.workflow_run.event == 'push'" \
    'github.event.workflow_run.head_repository.full_name == github.repository'
}

staging_verify_compares_head_with_main_tip() {
  local text
  text=$(workflow_job_text "$staging_workflow" verify)
  [ -n "$text" ] || return 1
  text_contains_all "$text" 'github.event.workflow_run.head_sha' main || return 1
  grep -Eq 'gh api|git (ls-remote|rev-parse|fetch)' <<<"$text"
}

staging_deploy_needs_verify() {
  all_exist "$staging_workflow" || return 1
  workflow_job_needs "$staging_workflow" deploy verify
}

production_verify_checks_tag_is_on_main() {
  local text
  text=$(workflow_job_text "$production_workflow" verify)
  [ -n "$text" ] || return 1
  text_contains_all "$text" 'git merge-base --is-ancestor' 'origin/main' || return 1
  grep -Eq 'github\.sha|GITHUB_SHA' <<<"$text"
}

production_verify_checkout_is_full_and_pinned() {
  local text
  text=$(workflow_job_text "$production_workflow" verify)
  grep -Eq 'uses: actions/checkout@[0-9a-f]{40}' <<<"$text" || return 1
  text_contains_all "$text" 'fetch-depth: 0'
}

production_deploy_needs_verify() {
  all_exist "$production_workflow" || return 1
  workflow_job_needs "$production_workflow" deploy verify
}

# deploy_ssh_call_text: the ssh -i command in deploy.yml, from its first line to the last continued line.
deploy_ssh_call_text() {
  awk '/ssh -i / { found = 1 } found { print; if ($0 !~ /\\$/) exit }' "$deploy_workflow"
}

deploy_ssh_is_hardened() {
  local text
  all_exist "$deploy_workflow" || return 1
  text=$(deploy_ssh_call_text)
  [ -n "$text" ] || return 1
  text_contains_all "$text" '-F /dev/null' 'GlobalKnownHostsFile=/dev/null' 'ConnectTimeout=' 'PasswordAuthentication=no'
}

deploy_user_is_validated_before_ssh() {
  local validate_line ssh_line
  all_exist "$deploy_workflow" || return 1
  validate_line=$(grep -nE '"\$DEPLOY_USER" =~ \^' "$deploy_workflow" | head -n 1 | cut -d: -f1)
  ssh_line=$(grep -nE '^ +ssh -i ' "$deploy_workflow" | head -n 1 | cut -d: -f1)
  [ -n "$validate_line" ] && [ -n "$ssh_line" ] && [ "$validate_line" -lt "$ssh_line" ]
}

runbook_binds_forced_command_per_key() {
  grep -Eq 'command="[^"]*deploy-forced staging"' "$deploy_runbook" &&
    grep -Eq 'command="[^"]*deploy-forced production"' "$deploy_runbook"
}

runbook_forced_command_runs_under_env_i() {
  file_contains "$deploy_runbook" 'env -i' && grep -Eiq 'root-owned (config|configuration)' "$deploy_runbook"
}

runbook_sets_permit_user_environment_no() {
  file_contains "$deploy_runbook" 'PermitUserEnvironment no'
}

runbook_scripts_are_root_owned_and_not_writable() {
  grep -Eiq 'root-owned (scripts|deploy scripts)' "$deploy_runbook" &&
    grep -Eiq 'not writable by the deploy user' "$deploy_runbook"
}

runbook_rollback_toggles_between_last_two() {
  grep -Eiq 'toggl[a-z]* between the last two releases' "$deploy_runbook"
}

runbook_restricts_both_environments_to_refs() {
  grep -Ei 'deployment (branch|tag)' "$deploy_runbook" | grep -Eiq 'staging' &&
    grep -Ei 'deployment (branch|tag)' "$deploy_runbook" | grep -Eiq 'production'
}

check "no deploy workflow uses the substring( expression, which actionlint rejects" workflows_avoid_substring
check "actionlint passes on every workflow (rhysd/actionlint 1.7.7, pinned by digest)" actionlint_passes_on_workflows
check "deploy workflows staging and production never use secrets: inherit" workflows_do_not_inherit_secrets
check "staging deploy is gated on a push event from this repository, not a fork" staging_deploy_is_gated_on_push_from_this_repo
check "staging has a verify job that compares workflow_run.head_sha with the tip of main" staging_verify_compares_head_with_main_tip
check "staging deploy needs the verify job" staging_deploy_needs_verify
check "production verify job checks the tagged commit is an ancestor of origin/main" production_verify_checks_tag_is_on_main
check "production verify checkout uses fetch-depth 0 and a sha-pinned action" production_verify_checkout_is_full_and_pinned
check "production deploy needs the verify job" production_deploy_needs_verify
check "deploy ssh call uses -F /dev/null, GlobalKnownHostsFile, ConnectTimeout and PasswordAuthentication=no" deploy_ssh_is_hardened
check "deploy validates DEPLOY_USER with a regex before the ssh call" deploy_user_is_validated_before_ssh
check "deploy runbook binds the forced command per key: deploy-forced staging and deploy-forced production" runbook_binds_forced_command_per_key
check "deploy runbook documents the env -i wrapper with root-owned config" runbook_forced_command_runs_under_env_i
check "deploy runbook sets PermitUserEnvironment no" runbook_sets_permit_user_environment_no
check "deploy runbook: root-owned scripts, not writable by the deploy user" runbook_scripts_are_root_owned_and_not_writable
check "deploy runbook: rollback toggles between the last two releases" runbook_rollback_toggles_between_last_two
check "deploy runbook: both GitHub environments restrict deployment branches and tags" runbook_restricts_both_environments_to_refs

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
