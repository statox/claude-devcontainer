#!/bin/bash
# shellcheck shell=bash
# Resolves which container engine (docker or podman) the ccc* scripts should
# use, and exports the variables every script needs to invoke it uniformly.
#
# Selection order:
#   1. CLAUDE_DEVCONTAINER_ENGINE env var, if set — must name an available
#      binary or this fails loudly rather than silently falling back.
#   2. Auto-detect: docker if present and its daemon responds, else podman.
#   3. Neither found: fail with a pointer to README setup.
#
# Sourced by ccc, ccc-code, ccc-compose, ccc-rebuild. Assumes the caller has
# `set -euo pipefail` active.

_engine_sh_fail() {
    echo "engine.sh: $1" >&2
    return 1
}

_resolve_engine() {
    if [ -n "${CLAUDE_DEVCONTAINER_ENGINE:-}" ]; then
        case "$CLAUDE_DEVCONTAINER_ENGINE" in
            docker|podman) ;;
            *) _engine_sh_fail "CLAUDE_DEVCONTAINER_ENGINE must be 'docker' or 'podman', got '$CLAUDE_DEVCONTAINER_ENGINE'"; return 1 ;;
        esac
        if ! command -v "$CLAUDE_DEVCONTAINER_ENGINE" >/dev/null 2>&1; then
            _engine_sh_fail "CLAUDE_DEVCONTAINER_ENGINE=$CLAUDE_DEVCONTAINER_ENGINE set, but '$CLAUDE_DEVCONTAINER_ENGINE' is not on PATH"
            return 1
        fi
        echo "$CLAUDE_DEVCONTAINER_ENGINE"
        return 0
    fi

    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        echo "docker"
        return 0
    fi

    if command -v podman >/dev/null 2>&1; then
        echo "podman"
        return 0
    fi

    _engine_sh_fail "no working container engine found (looked for docker, then podman). Install one, or set CLAUDE_DEVCONTAINER_ENGINE. See README.md."
    return 1
}

ENGINE_BIN="$(_resolve_engine)"
export ENGINE_BIN

COMPOSE_CMD="$ENGINE_BIN compose"
export COMPOSE_CMD

if [ "$ENGINE_BIN" = "podman" ]; then
    COMPOSE_FILES="-f docker-compose.yml -f docker-compose.podman.yml"
else
    COMPOSE_FILES="-f docker-compose.yml"
fi
export COMPOSE_FILES
