#!/bin/bash

set -euo pipefail

if [ -z "${CLAUDE_DEVCONTAINER_HOME:-}" ]; then
  echo "CLAUDE_DEVCONTAINER_HOME is not set. See README.md for setup." >&2
  exit 1
fi

DEVCONTAINER_DIR="$CLAUDE_DEVCONTAINER_HOME/devcontainer"
export WORKSPACE_FOLDER
WORKSPACE_FOLDER="$(pwd -P)"

# shellcheck source=SCRIPTDIR/engine.sh
source "$DEVCONTAINER_DIR/scripts/lib/engine.sh"

# Passed into the agent container so files created there are owned by the host user.
export DEV_UID DEV_GID
DEV_UID="$(id -u)"
DEV_GID="$(id -g)"

# Per-workspace compose project name for the agent container:
# - slug the directory name
# - short hash of the slug
# Allow unique name by repo
export AGENT_COMPOSE_PROJECT_NAME
_slug="$(basename "$WORKSPACE_FOLDER" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-')"
_slug="$(echo "$_slug" | sed -e 's/-\{2,\}/-/g' -e 's/^-//' -e 's/-$//')"
[ -n "$_slug" ] || _slug="workspace"
_hash="$(printf '%s' "$WORKSPACE_FOLDER" | sha1sum | cut -c1-8)"
AGENT_COMPOSE_PROJECT_NAME="${_slug}-${_hash}"

# Context7 credentials
# The env file is outside the repo to avoid mounting it in claude container
# The file is used in docker-compose files to provide creds only to the mcp container
MCP_CREDS_ENV_DIR="${MCP_CREDS_ENV_DIR:-$HOME/.config/claude-devcontainer}"
export CONTEXT7_ENV_FILE="$MCP_CREDS_ENV_DIR/context7.env"
[ -f "$CONTEXT7_ENV_FILE" ] || CONTEXT7_ENV_FILE=/dev/null
