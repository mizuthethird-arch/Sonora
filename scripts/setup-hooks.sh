#!/bin/sh
# Activates the repository git hooks. Run once after cloning.
set -eu
cd "$(dirname "$0")/.."
git config core.hooksPath .githooks
