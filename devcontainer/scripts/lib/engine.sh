#!/bin/bash
# Detect which container engine (docker or podman) to use, and export the
# variables the ccc* scripts build their commands from.
#
# Callers must set DEVCONTAINER_DIR before sourcing this file.
#
# CLAUDE_DEVCONTAINER_ENGINE, if set, forces the choice ("docker" or
# "podman") and fails loudly if that binary isn't installed — no silent
# fallback. Otherwise: prefer docker if its daemon is reachable, else fall
# back to podman if installed. Detection re-runs on every invocation
# (cheap) rather than being cached, so installing/removing an engine
# mid-session is picked up immediately.

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
    # `podman compose` is a dispatcher, not a self-contained implementation —
    # it shells out to an external provider (docker-compose or
    # podman-compose) that must be installed separately.
    $COMPOSE_CMD version >/dev/null 2>&1 \
        || _engine_die "podman compose has no working provider. Install podman-compose (e.g. 'pip install podman-compose' or your distro's package) and retry. See README.md."
    # podman-compose doesn't support Docker Compose v2's `--wait` flag; the
    # singleton services define no healthchecks, so it doesn't buy anything
    # under Podman anyway.
    COMPOSE_UP_FLAGS="-d"
else
    COMPOSE_FILE="$DEVCONTAINER_DIR/docker-compose.yml"
    COMPOSE_UP_FLAGS="-d --wait"
fi

export ENGINE_BIN COMPOSE_CMD COMPOSE_FILE COMPOSE_UP_FLAGS
