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
check "compose defines a workspace service" bash -c "docker compose config --services | grep -qx workspace"
check "workspace image pins a node version" bash -c "grep -Eq '^ARG NODE_VERSION=[0-9]+\.[0-9]+\.[0-9]+$' Dockerfile"
check "pnpm version is pinned in package.json" bash -c "grep -Eq '\"packageManager\": \"pnpm@[0-9]+\.[0-9]+\.[0-9]+\"' package.json"
check "workspace declares apps and packages" bash -c "grep -q 'apps/\*' pnpm-workspace.yaml && grep -q 'packages/\*' pnpm-workspace.yaml"
check "dockerignore excludes node_modules and env files" bash -c "grep -qx 'node_modules' .dockerignore && grep -qx '.env*' .dockerignore"
check "gitignore excludes env files" bash -c "grep -qx '.env*' .gitignore"
check "workflow runs on pull requests to dev and main" bash -c "grep -Eq 'branches: \[dev, main\]' $workflow && grep -q 'pull_request:' $workflow"
check "workflow runs on pushes to dev and main" bash -c "grep -q 'push:' $workflow"
check "workflow goes through docker compose" bash -c "grep -q 'docker compose' $workflow"
check "workflow pins actions to a commit sha" bash -c "grep -q 'uses: .*@[0-9a-f]\{40\}' $workflow && ! grep -E 'uses: .+@(v[0-9]|main|master|latest)' $workflow"
check "workflow requests read-only permissions" bash -c "grep -q 'contents: read' $workflow"
check "workflow scans for secrets" bash -c "grep -qi 'gitleaks' $workflow"
check "dependabot covers npm, docker and github-actions" bash -c "grep -q 'package-ecosystem: npm' .github/dependabot.yml && grep -q 'package-ecosystem: docker' .github/dependabot.yml && grep -q 'package-ecosystem: github-actions' .github/dependabot.yml"
check "pipeline command passes inside the workspace container" docker compose run --rm --build workspace pnpm run ci

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
