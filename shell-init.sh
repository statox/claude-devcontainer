# shellcheck shell=bash
# Source this file from your shell rc (~/.bashrc, ~/.zshrc) after setting
# CLAUDE_DEVCONTAINER_HOME to the path where this repo is cloned:
#
#   export CLAUDE_DEVCONTAINER_HOME="$HOME/path/to/claude_devcontainer"
#   source "$CLAUDE_DEVCONTAINER_HOME/shell-init.sh"
#
# Defines the host-side commands for entering/managing the Claude agent
# devcontainer. See README.md for the full workflow.

if [ -z "${CLAUDE_DEVCONTAINER_HOME:-}" ]; then
    echo "shell-init.sh: CLAUDE_DEVCONTAINER_HOME is not set, skipping alias setup." >&2
    return 0 2>/dev/null || exit 0
fi

alias ccc="$CLAUDE_DEVCONTAINER_HOME/devcontainer/scripts/ccc"
alias ccc-compose="$CLAUDE_DEVCONTAINER_HOME/devcontainer/scripts/ccc-compose"
alias ccc-rebuild="$CLAUDE_DEVCONTAINER_HOME/devcontainer/scripts/ccc-rebuild"
alias ccc-code="$CLAUDE_DEVCONTAINER_HOME/devcontainer/scripts/ccc-code"
