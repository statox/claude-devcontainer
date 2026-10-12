#!/bin/bash
set -euo pipefail

# Agent container provisioning:
# - Symlink config files
# - Install MCP
# - Install claude plugins
# - Install repo tools with mise
# - Create shell aliases
#
# Runs on every `ccc` and `ccc-rebuild`.
# Keep steps idempotent and fast.

# Symlink claude/ config files from this repo into ~/.claude.
# Changes are tracked on the host.
CLAUDE_HOME="$HOME/.claude"
REPO_CLAUDE="$HOME/.claude-devcontainer/claude"

mkdir -p "$CLAUDE_HOME"

# Replace a skills directory created by the container with the symlink
if [ -d "$CLAUDE_HOME/skills" ] && [ ! -L "$CLAUDE_HOME/skills" ]; then
    rm -rf "$CLAUDE_HOME/skills"
fi

# Symlink the config files and directories from claude/
if [ -d "$REPO_CLAUDE" ]; then
    for f in "$REPO_CLAUDE"/*; do
        # -n replaces an existing symlink instead of nesting into it
        ln -sfn "$f" "$CLAUDE_HOME/$(basename "$f")"
    done
fi

# Merge mcp-servers.json into ~/.claude.json.
# mcp-servers.json wins on conflict.
MCP_SERVERS_FILE="$REPO_CLAUDE/mcp-servers.json"
CLAUDE_JSON="$HOME/.claude.json"
if [ -f "$MCP_SERVERS_FILE" ]; then
    [ -f "$CLAUDE_JSON" ] || echo '{}' > "$CLAUDE_JSON"
    # ~/.claude.json is a mount point: rewrite it in place
    jq --slurpfile mcp "$MCP_SERVERS_FILE" \
        '.mcpServers = ((.mcpServers // {}) + $mcp[0])' \
        "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp"
    cat "$CLAUDE_JSON.tmp" > "$CLAUDE_JSON"
    rm "$CLAUDE_JSON.tmp"
fi

# Install marketplaces and plugins from plugins.json.
# Marketplaces match by GitHub source: owner/repo.
# Plugins match by installed id: name@marketplace.
# Installed ones are skipped.
PLUGINS_FILE="$REPO_CLAUDE/plugins.json"
if [ -f "$PLUGINS_FILE" ] && command -v claude >/dev/null 2>&1; then
    # Run from $HOME: the claude mise shim must not load the repo's config.
    (
        cd "$HOME"
        known_marketplaces="$(claude plugin marketplace list --json 2>/dev/null || echo '[]')"
        while IFS= read -r marketplace; do
            [ -n "$marketplace" ] || continue
            echo "$known_marketplaces" | jq -e --arg src "$marketplace" \
                'any(.[]; .repo == $src)' >/dev/null \
                || claude plugin marketplace add "$marketplace"
        done < <(jq -r '.marketplaces[]' "$PLUGINS_FILE")

        installed_plugins="$(claude plugin list --json 2>/dev/null || echo '[]')"
        while IFS= read -r plugin; do
            [ -n "$plugin" ] || continue
            echo "$installed_plugins" | jq -e --arg id "$plugin" \
                'any(.[]; .id == $id)' >/dev/null \
                || claude plugin install "$plugin" --scope user
        done < <(jq -r '.plugins[]' "$PLUGINS_FILE")
    )
fi

# Install the repo's [tools] as dev.
# provision-root.sh installs system packages before this script.
# Paranoid mode: the repo config needs explicit trust.
# Trust decisions persist in the mise-state volume.
if (cd /workdir && mise trust --show 2>/dev/null | grep -q ': untrusted$'); then
    echo "==> Trust prompt 2/2: tools, as dev."
    echo "    Trusting the repo's mise config installs its [tools] as dev."
fi
mise install

# Aliases to start claude in the container
echo "alias cc='claude'" > /home/dev/.bash_aliases
echo "alias ccd='claude --dangerously-skip-permissions'" >> /home/dev/.bash_aliases
