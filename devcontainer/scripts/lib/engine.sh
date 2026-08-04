#!/bin/bash
# Detect which container engine (docker or podman) to use, and export the
# variables the ccc* scripts build their commands from.
#
# Callers must set DEVCONTAINER_DIR before sourcing this file.
#
# if CLAUDE_DEVCONTAINER_ENGINE is set
#   force docker or podman
#   fails if the specified engine is not available
# else use Docker if its installed and its deamon is reachable
# else use Podman if installed
# else fail

_engine_die() {
    echo "engine.sh: $1" >&2
    exit 1
}

if [ -n "${CLAUDE_DEVCONTAINER_ENGINE:-}" ]; then
    ENGINE_BIN="$CLAUDE_DEVCONTAINER_ENGINE"
    command -v "$ENGINE_BIN" >/dev/null 2>&1 \
        || _engine_die "CLAUDE_DEVCONTAINER_ENGINE=$ENGINE_BIN but '$ENGINE_BIN' is not installed."
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    ENGINE_BIN="docker"
elif command -v podman >/dev/null 2>&1; then
    ENGINE_BIN="podman"
else
    _engine_die "no container engine found. Install Docker or Podman (4.7+), or set CLAUDE_DEVCONTAINER_ENGINE. See README.md."
fi

COMPOSE_CMD="$ENGINE_BIN compose"

if [ "$ENGINE_BIN" = "podman" ]; then
    COMPOSE_FILE="$DEVCONTAINER_DIR/docker-compose.podman.yml"
    AGENT_COMPOSE_FILE="$DEVCONTAINER_DIR/docker-compose.agent.podman.yml"
    # `podman compose` needs docker-compose or podman-compose installed
    $COMPOSE_CMD version >/dev/null 2>&1 \
        || _engine_die "podman compose has no working provider. Install podman-compose (e.g. 'pip install podman-compose' or your distro's package) and retry. See README.md."
    # podman-compose doesn't support Docker Compose v2's `--wait` flag
    # and the singleton services define no healthchecks
    # So we don't use it here
    COMPOSE_UP_FLAGS="-d"
else
    COMPOSE_FILE="$DEVCONTAINER_DIR/docker-compose.yml"
    AGENT_COMPOSE_FILE="$DEVCONTAINER_DIR/docker-compose.agent.yml"
    COMPOSE_UP_FLAGS="-d --wait"
fi

export ENGINE_BIN COMPOSE_CMD COMPOSE_FILE AGENT_COMPOSE_FILE COMPOSE_UP_FLAGS
