#!/bin/bash

set -euo pipefail

if [ -z "${CLAUDE_DEVCONTAINER_HOME:-}" ]; then
  echo "CLAUDE_DEVCONTAINER_HOME is not set. See README.md for setup." >&2
  exit 1
fi

DEVCONTAINER_DIR="$CLAUDE_DEVCONTAINER_HOME/devcontainer"
DEVCONTAINER_JSON="$DEVCONTAINER_DIR/devcontainer.json"
WORKSPACE_FOLDER="$(pwd)"

# shellcheck source=SCRIPTDIR/engine.sh
source "$DEVCONTAINER_DIR/scripts/lib/engine.sh"

# Passed into the devcontainer so files created there are owned by the host user.
export DEV_UID DEV_GID
DEV_UID="$(id -u)"
DEV_GID="$(id -g)"
