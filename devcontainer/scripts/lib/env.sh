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
export DEV_UID
DEV_UID="$(id -u)"

# Context7 credentials
# The env file is outside the repo to avoid mounting it in claude container
# The file is used in docker-compose files to provide creds only to the mcp container
MCP_CREDS_ENV_DIR="${MCP_CREDS_ENV_DIR:-$HOME/.config/claude-devcontainer}"
export CONTEXT7_ENV_FILE="$MCP_CREDS_ENV_DIR/context7.env"
[ -f "$CONTEXT7_ENV_FILE" ] || CONTEXT7_ENV_FILE=/dev/null
