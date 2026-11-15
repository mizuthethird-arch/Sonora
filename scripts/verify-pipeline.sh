#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

failures=0

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

workflow=".github/workflows/ci.yml"

check "compose file is valid" docker compose config --quiet
check "compose defines workspace and gitleaks services" bash -c "docker compose config --services | grep -qx workspace && docker compose --profile tools config --services | grep -qx gitleaks"
check "workspace image is pinned by version and digest" bash -c "grep -Eq '^FROM node:[0-9]+\.[0-9]+\.[0-9]+-alpine@sha256:[0-9a-f]{64} AS workspace$' Dockerfile"
check "workspace container runs as a non-root user" bash -c "grep -qx 'USER node' Dockerfile"
check "gitleaks image is pinned by version and digest" bash -c "grep -Eq 'image: zricethezav/gitleaks:v[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}' docker-compose.yml"
check "gitleaks mounts the repository read-only" bash -c "grep -q '\.:/repo:ro' docker-compose.yml"
check "pnpm version is pinned in package.json" bash -c "grep -Eq '\"packageManager\": \"pnpm@[0-9]+\.[0-9]+\.[0-9]+\"' package.json"
check "ci script runs audit, lint, typecheck, test and build in order" bash -c "grep -Eq '\"ci\": \".*audit:dependencies.*lint.*typecheck.*test.*build' package.json"
check "workspace declares apps and packages" bash -c "grep -q 'apps/\*' pnpm-workspace.yaml && grep -q 'packages/\*' pnpm-workspace.yaml"
check "base compose has no bind mount, override adds it" bash -c "! grep -q '\.:/workspace' docker-compose.yml && grep -q '\.:/workspace' docker-compose.override.yml"
check "dockerignore excludes dependencies, git data and secrets" bash -c "for entry in '**/node_modules' .git '**/.env*' '**/.npmrc' '**/*.pem' '**/*.key' '**/dist' '**/coverage'; do grep -Fqx \"\$entry\" .dockerignore || exit 1; done"
check "gitignore excludes env files and credentials" bash -c "for entry in '.env*' .npmrc '*.pem' '*.key'; do grep -Fqx \"\$entry\" .gitignore || exit 1; done"
check "workflow runs on pull requests to dev and main" bash -c "tr '\n' ' ' < $workflow | grep -Eq 'pull_request:[[:space:]]+branches: \[dev, main\]'"
check "workflow runs on pushes to dev and main" bash -c "tr '\n' ' ' < $workflow | grep -Eq 'push:[[:space:]]+branches: \[dev, main\]'"
check "workflow runner is pinned" bash -c "grep -q 'runs-on: ubuntu-24.04' $workflow"
check "workflow cancels superseded runs only on pull requests" bash -c "grep -q \"cancel-in-progress: \\\${{ github.event_name == 'pull_request' }}\" $workflow"
check "workflow runs gitleaks and the pipeline through docker compose without the dev override" bash -c "grep -Eq 'run: docker compose -f docker-compose.yml run --rm gitleaks' $workflow && grep -Eq 'run: docker compose -f docker-compose.yml run --rm workspace pnpm run ci' $workflow"
check "workflow pins actions to a commit sha" bash -c "grep -q 'uses: .*@[0-9a-f]\{40\}' $workflow && ! grep -E 'uses: .+@(v[0-9]|main|master|latest)' $workflow"
check "workflow requests read-only permissions" bash -c "grep -q 'contents: read' $workflow"
check "pre-commit hook scans staged changes for secrets" bash -c "test -x .githooks/pre-commit && grep -q 'gitleaks' .githooks/pre-commit && grep -q -- '--staged' .githooks/pre-commit"
check "dependabot covers npm, docker, docker-compose and github-actions" bash -c "for ecosystem in npm docker docker-compose github-actions; do grep -Eq \"package-ecosystem: \$ecosystem\\$\" .github/dependabot.yml || exit 1; done"
check "hook setup script exists and is executable" bash -c "test -x scripts/setup-hooks.sh && grep -q 'core.hooksPath .githooks' scripts/setup-hooks.sh"
check "git hooks are activated (run scripts/setup-hooks.sh)" bash -c "test \"\$(git config core.hooksPath)\" = .githooks"
check "secret scan finds no leaks" docker compose -f docker-compose.yml run --rm gitleaks
check "pipeline command passes inside the workspace container as CI runs it" docker compose -f docker-compose.yml run --rm --build workspace pnpm run ci

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
