#!/bin/sh
# Hot-reload loop for the API container. pnpm runs this with apps/api as the working directory.
# 1. Build once, so dist/ exists before node starts (the build also runs prisma generate).
# 2. Start tsc in watch mode in the background, so every edit in src/ is re-emitted to dist/.
# 3. Run node --watch in the foreground. It restarts the server whenever dist/ changes.
# The script does not use exec for node, because exec would replace the shell and the trap would never run.
# The EXIT trap stops the background watcher when node exits, so no tsc process is left behind.
set -eu

pnpm run build

tsc -p tsconfig.build.json --watch --preserveWatchOutput &
watcher_pid=$!
trap 'kill "$watcher_pid" 2>/dev/null || true' EXIT

node --watch dist/index.js
