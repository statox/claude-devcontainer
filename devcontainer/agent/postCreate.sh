#!/bin/bash
set -euo pipefail

# ~/.claude is a persistent named volume (session state, projects/, shell-snapshots/, etc.)
# In every container we symlink the config files from claude/ in this repo
# to ~/.claude in the container.
# This way this repo can track the modifications from the host and from the container
CLAUDE_HOME="$HOME/.claude"
REPO_CLAUDE="$HOME/.claude-devcontainer/claude"

mkdir -p "$CLAUDE_HOME"

# If the container created the skills directory before us we remove it before
# creating the symlink
if [ -d "$CLAUDE_HOME/skills" ] && [ ! -L "$CLAUDE_HOME/skills" ]; then
    rm -rf "$CLAUDE_HOME/skills"
fi

# Symlink the config files and directories from claude/
if [ -d "$REPO_CLAUDE" ]; then
    for f in "$REPO_CLAUDE"/*; do
        # Use -n to prevent ln from nesting the file if it already exists
        # in the container
        ln -sfn "$f" "$CLAUDE_HOME/$(basename "$f")"
    done
fi

# Merge the custom mcp-servers.json config into the final ~/.claude.json of
# the container.
# Idempotent, always take the version from mcp-servers.json in case of conflict
MCP_SERVERS_FILE="$REPO_CLAUDE/mcp-servers.json"
CLAUDE_JSON="$HOME/.claude.json"
if [ -f "$MCP_SERVERS_FILE" ]; then
    [ -f "$CLAUDE_JSON" ] || echo '{}' > "$CLAUDE_JSON"
    # We can't rm ~/.claude.json because it is a mount point, rewrite it instead
    jq --slurpfile mcp "$MCP_SERVERS_FILE" \
        '.mcpServers = ((.mcpServers // {}) + $mcp[0])' \
        "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp"
    cat "$CLAUDE_JSON.tmp" > "$CLAUDE_JSON"
    rm "$CLAUDE_JSON.tmp"
fi

# Install plugins from the custom plugins.json
# - Marketplaces matched by GitHub source ("owner/repo")
# - Plugins by their installed "id" ("name@marketplace")
# Skip already installed marketplaces/plugins
PLUGINS_FILE="$REPO_CLAUDE/plugins.json"
if [ -f "$PLUGINS_FILE" ] && command -v claude >/dev/null 2>&1; then
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
fi

# Run mise to install tooling if the container has a mise configuration
# -E preserves MISE_*/PATH so root resolves the same config/data dirs as dev.
sudo -E mise bootstrap --yes

# Aliases to start claude in the container
echo "alias cc='claude'" >> /home/dev/.bash_aliases
echo "alias ccd='claude --dangerously-skip-permissions'" >> /home/dev/.bash_aliases
