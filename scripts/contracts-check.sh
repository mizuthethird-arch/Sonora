#!/usr/bin/env bash
# Checks the committed API contract against the base branch: a breaking change needs a version bump and a noted overlap.
# Usage: scripts/contracts-check.sh <base-ref>, for example origin/dev in a pull request.
set -euo pipefail

cd "$(dirname "$0")/.."

readonly OASDIFF_IMAGE="tufin/oasdiff@sha256:004bef22058ace818b61f0eb2f05efb89fc6a3882f68bf4db0b6a86f40723fe0"
readonly CONTRACT_DIR="packages/contracts"

base_ref="${1:-}"
if [ -z "$base_ref" ]; then
  echo "usage: scripts/contracts-check.sh <base-ref>" >&2
  exit 2
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if ! git cat-file -e "$base_ref:$CONTRACT_DIR/openapi.json" 2>/dev/null; then
  echo "no contract on $base_ref yet; nothing to compare"
  exit 0
fi

git show "$base_ref:$CONTRACT_DIR/openapi.json" > "$work/base-openapi.json"
git show "$base_ref:$CONTRACT_DIR/contract.json" > "$work/base-contract.json"
cp "$CONTRACT_DIR/openapi.json" "$work/current-openapi.json"
cp "$CONTRACT_DIR/contract.json" "$work/current-contract.json"

# The committed document must be exactly what the code generates.
docker compose -f docker-compose.yml run --rm --no-deps -T workspace sh -c \
  "cd $CONTRACT_DIR && pnpm run --silent build >/dev/null && node dist/cli/emit.js /dev/stdout" > "$work/generated.json"
if ! cmp -s "$work/generated.json" "$CONTRACT_DIR/openapi.json"; then
  echo "$CONTRACT_DIR/openapi.json is stale: run pnpm --filter @sonora/contracts run openapi:emit" >&2
  exit 1
fi

# oasdiff lists every change for the reviewer. The gate is the rule below.
docker run --rm -v "$work:/data:ro" "$OASDIFF_IMAGE" breaking /data/base-openapi.json /data/current-openapi.json || true

docker compose -f docker-compose.yml run --rm --no-deps -T -v "$work:/contracts-check:ro" workspace sh -c \
  "cd $CONTRACT_DIR && node dist/cli/check.js /contracts-check/base-openapi.json /contracts-check/current-openapi.json /contracts-check/base-contract.json /contracts-check/current-contract.json"
