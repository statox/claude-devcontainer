# claude_devcontainer Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Populate the new standalone `claude_devcontainer` repo with the Claude Code devcontainer feature extracted from `dotfiles_statox`, generalized to work from any clone location via `CLAUDE_DEVCONTAINER_HOME`, with no "dotfiles" terminology and the `claude`→`ccc` command rename.

**Architecture:** Copy each source file into the new repo's layout (`devcontainer/`, `claude/`, top-level `README.md`/`LICENSE`/`shell-init.sh`), rewriting only the parts that reference `~/.dotfiles`, the old `claude`/`code-devcontainer` command names, or the nvm workaround. No new abstractions — this is a lift-and-rename of working infrastructure.

**Tech Stack:** Bash scripts, Docker / Docker Compose, the `devcontainers` CLI (`npx @devcontainers/cli`), JSON config, Markdown docs.

## Global Constraints

- No mentions of the term "dotfiles" anywhere in the new repo (comments, docs, variable names, filenames).
- Path resolution via a single env var, `CLAUDE_DEVCONTAINER_HOME`, read by every script and config that needs the repo's location. No installer script writes to the user's shell rc automatically — README instructs the user to add two lines themselves.
- Host-side command renamed `claude` → `ccc`; scripts renamed `claude-devcontainer`→`ccc`, `claude-devcontainer-compose`→`ccc-compose`, `claude-devcontainer-rebuild`→`ccc-rebuild`, `code-devcontainer`→`ccc-code`.
- Drop the nvm lazy-load workaround from all scripts (its premise no longer applies after the rename).
- `claude/` config directory is migrated with its content unchanged, except `CLAUDE.md`'s title changes from "Personal Global Rules" to "Default Global Rules".
- Notifications/broker stay Linux + PulseAudio/D-Bus only; README documents this plus a TODO about a future opt-in rename to `linux-desktop-notifications`.
- MIT LICENSE file, copyright holder "statox".
- **I (the implementer) do not have Docker, `npx`, or the `devcontainers` CLI available.** Every step that needs to build an image, run a container, or run `docker compose` must be handed to the user as an explicit copy-pasteable command block with expected output, and the plan must wait for the user to report back the result before marking that step done. All other steps (file creation, `jq`/`bash -n`/`shellcheck` validation, `git` operations) are done directly.

---

## File Structure

```
claude_devcontainer/
├── README.md
├── LICENSE
├── shell-init.sh
├── devcontainer/
│   ├── devcontainer.json
│   ├── devcontainer-lock.json
│   ├── docker-compose.yml
│   ├── agent/
│   │   ├── Dockerfile
│   │   └── postCreate.sh
│   ├── broker/
│   │   ├── Dockerfile
│   │   └── handle-notify.sh
│   ├── mcp-everything/
│   │   └── Dockerfile
│   └── scripts/
│       ├── ccc
│       ├── ccc-compose
│       ├── ccc-rebuild
│       └── ccc-code
└── claude/
    ├── CLAUDE.md
    ├── settings.json
    ├── bell-notify.sh
    ├── bell.wav
    ├── mcp-servers.json
    ├── plugins.json
    ├── statusline-command.sh
    └── skills/
        └── repo-onboarding/
            ├── SKILL.md
            └── REPO_OVERVIEW_template.md
```

Source files live under `/workdir/dotfiles_statox/devcontainer/` and `/workdir/dotfiles_statox/claude/`. Destination is `/workdir/claude_devcontainer/`.

---

### Task 1: LICENSE and repo skeleton

**Files:**
- Create: `/workdir/claude_devcontainer/LICENSE`
- Create: `/workdir/claude_devcontainer/.gitignore`

**Interfaces:**
- Produces: a repo root ready for the `devcontainer/` and `claude/` subtrees added in later tasks.

- [ ] **Step 1: Create the LICENSE file**

```
MIT License

Copyright (c) 2026 statox

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Write this to `/workdir/claude_devcontainer/LICENSE`.

- [ ] **Step 2: Create .gitignore**

```
.venv-claude/
*.tmp
```

Write this to `/workdir/claude_devcontainer/.gitignore`.

- [ ] **Step 3: Commit**

```bash
cd /workdir/claude_devcontainer
git add LICENSE .gitignore
git commit -m "Add MIT license and gitignore"
```

---

### Task 2: mcp-everything container (unchanged copy)

**Files:**
- Create: `/workdir/claude_devcontainer/devcontainer/mcp-everything/Dockerfile`

**Interfaces:**
- Produces: the `mcp-everything` image build context, referenced by `docker-compose.yml` (Task 6).

No source references to "dotfiles" or old command names exist in this file — it's a straight copy.

- [ ] **Step 1: Copy the file verbatim**

```dockerfile
FROM node:22-alpine

RUN apk add --no-cache socat

RUN npm install -g @modelcontextprotocol/server-everything

# node:22-alpine already ships a non-root "node" user at uid 1000 for this
# purpose, so there's no need to create a separate one.
USER node

EXPOSE 3001
CMD ["socat", "TCP-LISTEN:3001,fork,reuseaddr", "EXEC:mcp-server-everything"]
```

Write this to `/workdir/claude_devcontainer/devcontainer/mcp-everything/Dockerfile`.

- [ ] **Step 2: Diff against the source to confirm it's an exact copy**

Run: `diff /workdir/dotfiles_statox/devcontainer/mcp-everything/Dockerfile /workdir/claude_devcontainer/devcontainer/mcp-everything/Dockerfile`
Expected: no output (files identical).

- [ ] **Step 3: Commit**

```bash
cd /workdir/claude_devcontainer
git add devcontainer/mcp-everything/Dockerfile
git commit -m "Add mcp-everything container"
```

---

### Task 3: broker container (unchanged copy)

**Files:**
- Create: `/workdir/claude_devcontainer/devcontainer/broker/Dockerfile`
- Create: `/workdir/claude_devcontainer/devcontainer/broker/handle-notify.sh`

**Interfaces:**
- Produces: the `broker` image build context, referenced by `docker-compose.yml` (Task 6).

Neither file references "dotfiles" or old command names — straight copies.

- [ ] **Step 1: Copy Dockerfile verbatim**

```dockerfile
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    dbus \
    libnotify-bin \
    pulseaudio-utils \
    socat \
    util-linux \
    && rm -rf /var/lib/apt/lists/*

COPY handle-notify.sh /usr/local/bin/handle-notify.sh
RUN chmod 755 /usr/local/bin/handle-notify.sh

RUN mkdir -p /run/broker && chmod 777 /run/broker

CMD ["socat", "UNIX-LISTEN:/run/broker/notify.sock,fork,unlink-early,mode=777", "EXEC:/usr/local/bin/handle-notify.sh"]
```

Write this to `/workdir/claude_devcontainer/devcontainer/broker/Dockerfile`.

- [ ] **Step 2: Copy handle-notify.sh verbatim**

```bash
#!/bin/sh
set -eu

IFS='|' read -r type message || true

case "$type" in
    waiting) urgency=low; icon=dialog-question ;;
    done)    urgency=low; icon=dialog-ok ;;
    *)       urgency=low; icon=dialog-information ;;
esac

echo "[broker] notify: type=${type} message=${message}" >&2

# socat tears down this process (and anything still attached to its session)
# as soon as the client closes the connection, which happens right after it
# sends its one line. paplay usually finishes before that race is lost, but
# notify-send's D-Bus round trip often doesn't. setsid detaches the actual
# work into its own session so it survives past this process's teardown.
# shellcheck disable=SC2016
setsid sh -c '
    paplay /claude-assets/bell.wav >/dev/null 2>&1 || true
    notify-send "$1" -a Claude -u "$2" -i "$3" -t 1500 || true
' -- "$message" "$urgency" "$icon" </dev/null >/dev/null 2>&1 &
```

Write this to `/workdir/claude_devcontainer/devcontainer/broker/handle-notify.sh`, then `chmod +x` it.

- [ ] **Step 3: Diff and shellcheck**

Run:
```bash
diff /workdir/dotfiles_statox/devcontainer/broker/Dockerfile /workdir/claude_devcontainer/devcontainer/broker/Dockerfile
diff /workdir/dotfiles_statox/devcontainer/broker/handle-notify.sh /workdir/claude_devcontainer/devcontainer/broker/handle-notify.sh
chmod +x /workdir/claude_devcontainer/devcontainer/broker/handle-notify.sh
shellcheck /workdir/claude_devcontainer/devcontainer/broker/handle-notify.sh
```
Expected: both `diff`s produce no output; `shellcheck` reports no errors (matches the source, which already passes).

- [ ] **Step 4: Commit**

```bash
cd /workdir/claude_devcontainer
git add devcontainer/broker/
git commit -m "Add broker container"
```

---

### Task 4: agent container — Dockerfile (unchanged) and postCreate.sh (rewritten)

**Files:**
- Create: `/workdir/claude_devcontainer/devcontainer/agent/Dockerfile`
- Create: `/workdir/claude_devcontainer/devcontainer/agent/postCreate.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: the `agent` image build context. `postCreate.sh` reads config from `/home/dev/.claude-devcontainer/claude` (the in-container mount path set up by `devcontainer.json` in Task 5) instead of `/home/dev/.dotfiles/claude`.

`agent/Dockerfile` has no "dotfiles" references — copy verbatim. `postCreate.sh` renames its `DOTFILES_CLAUDE` variable to `REPO_CLAUDE` and points it at the new mount path, and rewords comments that said "dotfiles-managed"/"dotfiles repo".

- [ ] **Step 1: Copy Dockerfile verbatim**

```dockerfile
# Builds mcp-language-server (Go binary) in an isolated stage so it doesn't
# depend on the node feature, which is layered onto this image by the
# devcontainers CLI *after* this Dockerfile builds.
FROM golang:1.24-alpine AS mcp-language-server-builder
RUN go install github.com/isaacphi/mcp-language-server@latest

FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    less \
    netcat-openbsd \
    openssh-client \
    ripgrep \
    shellcheck \
    socat \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Install the GitLab CLI (glab) from the official release .deb
ARG GLAB_VERSION=1.103.0
RUN curl -fsSL -o /tmp/glab.deb \
    "https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_VERSION}/downloads/glab_${GLAB_VERSION}_linux_amd64.deb" \
    && apt-get install -y --no-install-recommends /tmp/glab.deb \
    && rm -f /tmp/glab.deb /var/lib/apt/lists/* 2>/dev/null || true

COPY --from=mcp-language-server-builder /go/bin/mcp-language-server /usr/local/bin/mcp-language-server

# Create dev user with a known UID; devcontainer CLI's updateRemoteUserUID
# remaps this to match the host user at container-creation time.
RUN userdel -r ubuntu 2>/dev/null || true
RUN useradd -m -s /bin/bash -u 1000 dev

USER dev
WORKDIR /workdir

# Pre-create dirs owned by dev so named volumes mounted here inherit dev's
# ownership (1000) instead of being root-owned and unwritable.
RUN mkdir -p /home/dev/.config/glab-cli /home/dev/.claude /home/dev/.vscode-server

COPY --chown=dev:dev postCreate.sh /home/dev/postCreate.sh
RUN chmod 755 /home/dev/postCreate.sh
```

Write this to `/workdir/claude_devcontainer/devcontainer/agent/Dockerfile`. (The commented-out `python3`/`python3-pip`/`python3-venv` lines from the source are dropped — dead code the original already noted as superseded by the `uv` feature.)

- [ ] **Step 2: Write the rewritten postCreate.sh**

```bash
#!/bin/bash
set -euo pipefail

# ~/.claude is a persistent named volume (holds session state, projects/,
# shell-snapshots/, etc.). The config files tracked in this repo's claude/
# directory are symlinked in on every container creation so host <-> container
# edits stay live in both directions.
CLAUDE_HOME="$HOME/.claude"
REPO_CLAUDE="$HOME/.claude-devcontainer/claude"

mkdir -p "$CLAUDE_HOME"

# ~/.claude/skills is the one tracked entry that's a directory rather than a
# plain file. If it already exists as a real directory (e.g. a skill created
# directly inside a container before this symlink existed), `ln -sf <dir>
# <existing-dir>` below would nest a symlink inside it instead of replacing
# it. This repo's version always wins: clear out a real directory first.
if [ -d "$CLAUDE_HOME/skills" ] && [ ! -L "$CLAUDE_HOME/skills" ]; then
    rm -rf "$CLAUDE_HOME/skills"
fi

if [ -d "$REPO_CLAUDE" ]; then
    for f in "$REPO_CLAUDE"/*; do
        # -n: CLAUDE_HOME lives in a volume shared by every repo's container,
        # so on the second and later container creations this symlink already
        # exists. Without -n, `ln -sf` would dereference an existing
        # symlink-to-directory and nest the new link inside it instead of
        # replacing it - which is how a stray `skills/skills` symlink ended up
        # created inside the tracked skills/ directory itself.
        ln -sfn "$f" "$CLAUDE_HOME/$(basename "$f")"
    done
fi

# Merge the tracked mcpServers config into ~/.claude.json (a bind-mounted
# file, not part of the symlink loop above) without touching any of its
# other content. Idempotent: safe to re-run on every container creation, and
# any server keys present in mcp-servers.json always win over a stale entry
# left in ~/.claude.json from a previous run.
MCP_SERVERS_FILE="$REPO_CLAUDE/mcp-servers.json"
CLAUDE_JSON="$HOME/.claude.json"
if [ -f "$MCP_SERVERS_FILE" ]; then
    [ -f "$CLAUDE_JSON" ] || echo '{}' > "$CLAUDE_JSON"
    # ~/.claude.json is a bind mount (devcontainer.json), i.e. a mount point
    # in this container's mount namespace. `mv`/rename(2) onto a mount point
    # fails with EBUSY ("Device or resource busy") since it would require
    # detaching the mount. Overwrite the file's contents in place instead of
    # replacing the inode.
    jq --slurpfile mcp "$MCP_SERVERS_FILE" \
        '.mcpServers = ((.mcpServers // {}) + $mcp[0])' \
        "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp"
    cat "$CLAUDE_JSON.tmp" > "$CLAUDE_JSON"
    rm "$CLAUDE_JSON.tmp"
fi

# typescript-language-server backs the "typescript" MCP server
# (claude/mcp-servers.json), which runs mcp-language-server as a local stdio
# process against /workdir. Installed here rather than in agent/Dockerfile
# because npm only exists after the node feature is layered onto the image.
command -v typescript-language-server >/dev/null 2>&1 || npm install -g typescript typescript-language-server

# Install the Claude Code plugins declared in plugins.json (tracked in this
# repo) idempotently, on every container creation. Marketplaces are matched
# by GitHub source ("owner/repo"); plugins by their installed "id"
# ("name@marketplace"). Already-added marketplaces / already-installed
# plugins are skipped, so re-running this is a no-op except for anything new
# added to plugins.json since the last container creation.
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
```

Write this to `/workdir/claude_devcontainer/devcontainer/agent/postCreate.sh`, then `chmod +x` it.

- [ ] **Step 3: Validate with shellcheck and grep for leftover "dotfiles" mentions**

Run:
```bash
chmod +x /workdir/claude_devcontainer/devcontainer/agent/postCreate.sh
shellcheck /workdir/claude_devcontainer/devcontainer/agent/postCreate.sh
grep -ri dotfiles /workdir/claude_devcontainer/devcontainer/agent/postCreate.sh
```
Expected: `shellcheck` reports no errors; `grep` finds nothing (exits 1 with no output).

- [ ] **Step 4: Commit**

```bash
cd /workdir/claude_devcontainer
git add devcontainer/agent/
git commit -m "Add agent container"
```

---

### Task 5: devcontainer.json and devcontainer-lock.json

**Files:**
- Create: `/workdir/claude_devcontainer/devcontainer/devcontainer.json`
- Create: `/workdir/claude_devcontainer/devcontainer/devcontainer-lock.json`

**Interfaces:**
- Consumes: `agent/Dockerfile` (Task 4).
- Produces: the config read by `${localEnv:CLAUDE_DEVCONTAINER_HOME}` in every `ccc*` script (Task 7), and the `/home/dev/.claude-devcontainer` mount path that `postCreate.sh` (Task 4) reads from.

- [ ] **Step 1: Write devcontainer.json**

```json
{
    "name": "claude-agent",
    "build": {
        "dockerfile": "agent/Dockerfile",
        "context": "agent"
    },
    "features": {
        "ghcr.io/devcontainers/features/github-cli:1": {},
        "ghcr.io/devcontainers/features/node": {
            "version": "lts"
        },
        "ghcr.io/jsburckhardt/devcontainer-features/uv:1": {},
        "ghcr.io/stu-bell/devcontainer-features/claude-code:0": {}
    },
    "customizations": {
        "vscode": {
            "extensions": [
                "anthropic.claude-code"
            ]
        }
    },
    "workspaceFolder": "/workdir",
    "workspaceMount": "source=${localWorkspaceFolder},target=/workdir,type=bind",
    "remoteUser": "dev",
    "updateRemoteUserUID": true,
    "postCreateCommand": "/home/dev/postCreate.sh",
    "runArgs": [
        "--network=mcp-net"
    ],
    "shutdownAction": "stopContainer",
    "mounts": [
        "source=${localWorkspaceFolder}/.venv-claude,target=/workdir/.venv,type=bind",
        "source=claude-home,target=/home/dev/.claude,type=volume",
        "source=vscode-server,target=/home/dev/.vscode-server,type=volume",
        "source=glab-config,target=/home/dev/.config/glab-cli,type=volume",
        "source=broker-sock,target=/run/broker,type=volume",
        "source=${localEnv:CLAUDE_DEVCONTAINER_HOME},target=/home/dev/.claude-devcontainer,type=bind",
        "source=${localEnv:HOME}/.claude.json,target=/home/dev/.claude.json,type=bind",
        "source=${localEnv:HOME}/.netrc,target=/home/dev/.netrc,type=bind"
    ]
}
```

Write this to `/workdir/claude_devcontainer/devcontainer/devcontainer.json`.

- [ ] **Step 2: Copy devcontainer-lock.json verbatim**

Read `/workdir/dotfiles_statox/devcontainer/devcontainer-lock.json` and write its exact contents to `/workdir/claude_devcontainer/devcontainer/devcontainer-lock.json`. (This is a feature version/integrity pin file with no "dotfiles" references and no path assumptions — a straight copy. It gets regenerated in Task 11's manual verification, so an initially-stale copy is fine.)

- [ ] **Step 3: Validate JSON syntax**

Run:
```bash
jq empty /workdir/claude_devcontainer/devcontainer/devcontainer.json
jq empty /workdir/claude_devcontainer/devcontainer/devcontainer-lock.json
diff /workdir/dotfiles_statox/devcontainer/devcontainer-lock.json /workdir/claude_devcontainer/devcontainer/devcontainer-lock.json
```
Expected: both `jq empty` calls produce no output (valid JSON); `diff` produces no output.

- [ ] **Step 4: Commit**

```bash
cd /workdir/claude_devcontainer
git add devcontainer/devcontainer.json devcontainer/devcontainer-lock.json
git commit -m "Add devcontainer.json and lockfile"
```

---

### Task 6: docker-compose.yml

**Files:**
- Create: `/workdir/claude_devcontainer/devcontainer/docker-compose.yml`

**Interfaces:**
- Consumes: `broker/` (Task 3), `mcp-everything/` (Task 2).
- Produces: the compose file every `ccc*` script (Task 7) points `docker compose -f` at.

- [ ] **Step 1: Write docker-compose.yml**

```yaml
services:
  broker:
    build:
      context: ./broker
    network_mode: host
    user: "${DEV_UID}"
    # Ubuntu's AppArmor userspace mediation for D-Bus blocks the session bus
    # from Docker's default confined profile regardless of UID; the broker's
    # sole job is talking to that bus, so it runs unconfined.
    security_opt:
      - apparmor:unconfined
    restart: unless-stopped
    volumes:
      - broker-sock:/run/broker
      - /run/user/${DEV_UID}:/run/user/${DEV_UID}
      - ${CLAUDE_DEVCONTAINER_HOME}/claude:/claude-assets:ro
    environment:
      - PULSE_SERVER=unix:/run/user/${DEV_UID}/pulse/native
      - DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${DEV_UID}/bus

  mcp-everything:
    build:
      context: ./mcp-everything
    restart: unless-stopped
    networks:
      - mcp-net

networks:
  # Fixed name so the agent's `--network=mcp-net` runArg (devcontainer.json)
  # attaches to this network by name, rather than Compose's default
  # project-prefixed naming.
  mcp-net:
    name: mcp-net

volumes:
  # Fixed name so this matches the plain (non-Compose) volume reference the
  # agent's devcontainer.json mounts by name — otherwise Compose would
  # namespace it under the project name, a different volume the agent never sees.
  broker-sock:
    name: broker-sock
```

Write this to `/workdir/claude_devcontainer/devcontainer/docker-compose.yml`. (Only change from source: `${HOME}/.dotfiles/claude` → `${CLAUDE_DEVCONTAINER_HOME}/claude`.)

- [ ] **Step 2: Confirm no "dotfiles" references remain**

Run: `grep -i dotfiles /workdir/claude_devcontainer/devcontainer/docker-compose.yml`
Expected: no output (exits 1).

- [ ] **Step 3: Commit**

```bash
cd /workdir/claude_devcontainer
git add devcontainer/docker-compose.yml
git commit -m "Add docker-compose.yml"
```

---

### Task 7: host-side scripts (ccc, ccc-compose, ccc-rebuild, ccc-code)

**Files:**
- Create: `/workdir/claude_devcontainer/devcontainer/scripts/ccc`
- Create: `/workdir/claude_devcontainer/devcontainer/scripts/ccc-compose`
- Create: `/workdir/claude_devcontainer/devcontainer/scripts/ccc-rebuild`
- Create: `/workdir/claude_devcontainer/devcontainer/scripts/ccc-code`

**Interfaces:**
- Consumes: `$CLAUDE_DEVCONTAINER_HOME` env var (set by the user per README, Task 9); `devcontainer.json` (Task 5); `docker-compose.yml` (Task 6).
- Produces: the four commands aliased in `shell-init.sh` (Task 8).

Each script: (a) fails fast with a clear message if `CLAUDE_DEVCONTAINER_HOME` is unset, (b) resolves paths from that var instead of `$HOME/.dotfiles`, (c) drops the nvm lazy-load workaround.

- [ ] **Step 1: Write ccc**

```bash
#!/bin/bash
# Launch (or attach to) a per-workspace Claude agent devcontainer.
#
# Usage: cd into the project you want to work on, then run this script
# with no arguments. It brings up the global broker (see ccc-compose),
# starts/reuses the devcontainer for the current working directory, and
# drops you into a shell inside it.
#
# The broker is a separate, global-singleton compose project (one broker
# for all workspaces) that the agent container talks to for things like
# desktop notifications; it must be running before the agent container
# starts, which is why it's brought up first below.
set -euo pipefail

if [ -z "${CLAUDE_DEVCONTAINER_HOME:-}" ]; then
    echo "ccc: CLAUDE_DEVCONTAINER_HOME is not set. See README.md for setup." >&2
    exit 1
fi

DEVCONTAINER_DIR="$CLAUDE_DEVCONTAINER_HOME/devcontainer"
DEVCONTAINER_JSON="$DEVCONTAINER_DIR/devcontainer.json"

WORKSPACE_FOLDER="$(pwd)"

# Passed into the devcontainer so files created there are owned by the host user.
export DEV_UID
DEV_UID="$(id -u)"

# Bootstrap files/dirs the container expects to already exist on the host.
[ -e "$HOME/.claude.json" ] || echo "{}" > "$HOME/.claude.json"
mkdir -p "${WORKSPACE_FOLDER}/.venv-claude"

# Start the global singleton services (broker, mcp-everything, ...) — idempotent if already running.
docker compose -f "$DEVCONTAINER_DIR/docker-compose.yml" up -d --wait

# Create/start the workspace-scoped agent container, then exec a shell in it.
npx @devcontainers/cli up --workspace-folder "$WORKSPACE_FOLDER" --config "$DEVCONTAINER_JSON"
exec npx @devcontainers/cli exec --workspace-folder "$WORKSPACE_FOLDER" --config "$DEVCONTAINER_JSON" bash
```

- [ ] **Step 2: Write ccc-compose**

```bash
#!/bin/bash
# Thin wrapper around `docker compose` for the global singleton services
# project (broker, mcp-everything, ...), for diagnostics (e.g.
# `ccc-compose logs -f`, `ccc-compose ps`, `ccc-compose down`). These
# services are normally started automatically by ccc; use this script
# directly when you need to inspect or manage them outside of that flow.
#
# Usage: ccc-compose <any docker compose subcommand/args>
set -euo pipefail

if [ -z "${CLAUDE_DEVCONTAINER_HOME:-}" ]; then
    echo "ccc-compose: CLAUDE_DEVCONTAINER_HOME is not set. See README.md for setup." >&2
    exit 1
fi

# Passed through so the compose file's UID interpolation resolves correctly.
export DEV_UID
DEV_UID="$(id -u)"

exec docker compose -f "$CLAUDE_DEVCONTAINER_HOME/devcontainer/docker-compose.yml" "$@"
```

- [ ] **Step 3: Write ccc-rebuild**

```bash
#!/bin/bash
# Rebuild the per-workspace Claude agent devcontainer from scratch, picking up
# devcontainer.json/Dockerfile changes (new features, base image bumps, etc.)
# that a plain `ccc` run might not pick up because it reuses the existing
# container.
#
# Usage: cd into the project you want to rebuild, then run this script with
# no arguments. It removes the existing container and rebuilds the image
# without cache, then drops you into a shell inside the fresh container.
set -euo pipefail

if [ -z "${CLAUDE_DEVCONTAINER_HOME:-}" ]; then
    echo "ccc-rebuild: CLAUDE_DEVCONTAINER_HOME is not set. See README.md for setup." >&2
    exit 1
fi

DEVCONTAINER_DIR="$CLAUDE_DEVCONTAINER_HOME/devcontainer"
DEVCONTAINER_JSON="$DEVCONTAINER_DIR/devcontainer.json"

WORKSPACE_FOLDER="$(pwd)"

# Passed into the devcontainer so files created there are owned by the host user.
export DEV_UID
DEV_UID="$(id -u)"

# Bootstrap files/dirs the container expects to already exist on the host.
[ -e "$HOME/.claude.json" ] || echo "{}" > "$HOME/.claude.json"
mkdir -p "${WORKSPACE_FOLDER}/.venv-claude"

# Start the global singleton services (broker, mcp-everything, ...) — idempotent if already running.
echo "Start up singleton services"
docker compose -f "$DEVCONTAINER_DIR/docker-compose.yml" up -d --wait

# Force a fresh container and image build, then exec a shell in it.
echo "Rebuild devcontainer"
npx @devcontainers/cli up \
    --workspace-folder "$WORKSPACE_FOLDER" \
    --config "$DEVCONTAINER_JSON" \
    --remove-existing-container

echo "Start devcontainer"
exec npx @devcontainers/cli exec --workspace-folder "$WORKSPACE_FOLDER" --config "$DEVCONTAINER_JSON" bash
```

(Cleanup vs. source: dropped the stray trailing `#` comment line and the commented-out `# --build-no-cache` flag.)

- [ ] **Step 4: Write ccc-code**

```bash
#!/bin/bash
# Open VS Code attached to the per-workspace Claude agent devcontainer.
#
# Usage: cd into the project you want to work on, then run this script with
# no arguments. It brings up the global broker and the per-repo agent
# container, then opens VS Code already attached to that container with
# /workdir open, so the VS Code Claude Code extension runs confined inside it.
set -euo pipefail

if [ -z "${CLAUDE_DEVCONTAINER_HOME:-}" ]; then
    echo "ccc-code: CLAUDE_DEVCONTAINER_HOME is not set. See README.md for setup." >&2
    exit 1
fi

DEVCONTAINER_DIR="$CLAUDE_DEVCONTAINER_HOME/devcontainer"
DEVCONTAINER_JSON="$DEVCONTAINER_DIR/devcontainer.json"

WORKSPACE_FOLDER="$(pwd)"

# Passed into the devcontainer so files created there are owned by the host user.
export DEV_UID
DEV_UID="$(id -u)"

# Bootstrap files/dirs the container expects to already exist on the host.
[ -e "$HOME/.claude.json" ] || echo "{}" > "$HOME/.claude.json"
mkdir -p "${WORKSPACE_FOLDER}/.venv-claude"

# Start the global singleton services (broker, mcp-everything, ...) — idempotent if already running.
docker compose -f "$DEVCONTAINER_DIR/docker-compose.yml" up -d --wait

# Create/start the workspace-scoped agent container (idempotent: reuses the
# existing container for this workspace folder if one is already running,
# so running this script twice from the same directory attaches two VS Code
# windows to the same container rather than creating a second one).
npx @devcontainers/cli up --workspace-folder "$WORKSPACE_FOLDER" --config "$DEVCONTAINER_JSON"

# Find the container the CLI just created/reused, via the same
# `devcontainer.local_folder` label the CLI itself uses for this lookup.
CONTAINER_ID="$(docker ps -q --filter "label=devcontainer.local_folder=${WORKSPACE_FOLDER}")"
if [ -z "$CONTAINER_ID" ]; then
    echo "ccc-code: could not find a running agent container for $WORKSPACE_FOLDER" >&2
    exit 1
fi
CONTAINER_NAME="$(docker inspect -f '{{.Name}}' "$CONTAINER_ID")" # includes leading "/"

# NOTE: `vscode-remote://attached-container+<hex>` is an UNDOCUMENTED,
# internal VS Code URI scheme (reverse-engineered from community write-ups,
# not from official docs) — it may break across VS Code updates. The hex
# payload is `{"containerName":"/<name>"}`, JSON then hex-encoded. If this
# ever stops working, the stable fallback is fully manual: Command Palette
# -> "Dev Containers: Attach to Running Container..." -> pick this repo's
# container -> Open Folder -> /workdir.
HEX="$(printf '{"containerName":"%s"}' "$CONTAINER_NAME" | xxd -p | tr -d '\n')"

exec code --folder-uri "vscode-remote://attached-container+${HEX}/workdir"
```

- [ ] **Step 5: Make executable and validate**

Run:
```bash
chmod +x /workdir/claude_devcontainer/devcontainer/scripts/ccc \
         /workdir/claude_devcontainer/devcontainer/scripts/ccc-compose \
         /workdir/claude_devcontainer/devcontainer/scripts/ccc-rebuild \
         /workdir/claude_devcontainer/devcontainer/scripts/ccc-code

shellcheck /workdir/claude_devcontainer/devcontainer/scripts/ccc
shellcheck /workdir/claude_devcontainer/devcontainer/scripts/ccc-compose
shellcheck /workdir/claude_devcontainer/devcontainer/scripts/ccc-rebuild
shellcheck /workdir/claude_devcontainer/devcontainer/scripts/ccc-code

grep -ril dotfiles /workdir/claude_devcontainer/devcontainer/scripts/ || true
grep -ril nvm /workdir/claude_devcontainer/devcontainer/scripts/ || true
```
Expected: `shellcheck` reports no errors on any of the four scripts; both `grep` calls find nothing (no output, no matching files).

- [ ] **Step 6: Commit**

```bash
cd /workdir/claude_devcontainer
git add devcontainer/scripts/
git commit -m "Add ccc host-side scripts"
```

---

### Task 8: shell-init.sh

**Files:**
- Create: `/workdir/claude_devcontainer/shell-init.sh`

**Interfaces:**
- Consumes: `$CLAUDE_DEVCONTAINER_HOME` env var; script paths from Task 7.
- Produces: `ccc`, `ccc-compose`, `ccc-rebuild`, `ccc-code` shell aliases, sourced by the user per README (Task 9).

- [ ] **Step 1: Write shell-init.sh**

```bash
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
```

Write this to `/workdir/claude_devcontainer/shell-init.sh`.

- [ ] **Step 2: Validate with shellcheck**

Run: `shellcheck /workdir/claude_devcontainer/shell-init.sh`
Expected: no errors. (`SC2148` missing-shebang may fire since this file is meant to be sourced, not executed — if it does, add `# shellcheck shell=bash` as the first line and re-run.)

- [ ] **Step 3: Commit**

```bash
cd /workdir/claude_devcontainer
git add shell-init.sh
git commit -m "Add shell-init.sh"
```

---

### Task 9: claude/ config directory

**Files:**
- Create: `/workdir/claude_devcontainer/claude/CLAUDE.md`
- Create: `/workdir/claude_devcontainer/claude/settings.json`
- Create: `/workdir/claude_devcontainer/claude/bell-notify.sh`
- Create: `/workdir/claude_devcontainer/claude/bell.wav`
- Create: `/workdir/claude_devcontainer/claude/mcp-servers.json`
- Create: `/workdir/claude_devcontainer/claude/plugins.json`
- Create: `/workdir/claude_devcontainer/claude/statusline-command.sh`
- Create: `/workdir/claude_devcontainer/claude/skills/repo-onboarding/SKILL.md`
- Create: `/workdir/claude_devcontainer/claude/skills/repo-onboarding/REPO_OVERVIEW_template.md`

**Interfaces:**
- Consumes: nothing (self-contained config, symlinked in by `postCreate.sh` from Task 4).
- Produces: the `~/.claude` contents inside the agent container.

None of these files reference "dotfiles" except `CLAUDE.md`'s title. Copy everything verbatim except that one heading change.

- [ ] **Step 1: Copy the plain-file configs verbatim**

Run these copies (source → destination), preserving content and executable bits exactly:
```bash
mkdir -p /workdir/claude_devcontainer/claude/skills/repo-onboarding

cp /workdir/dotfiles_statox/claude/settings.json /workdir/claude_devcontainer/claude/settings.json
cp /workdir/dotfiles_statox/claude/bell-notify.sh /workdir/claude_devcontainer/claude/bell-notify.sh
cp /workdir/dotfiles_statox/claude/bell.wav /workdir/claude_devcontainer/claude/bell.wav
cp /workdir/dotfiles_statox/claude/mcp-servers.json /workdir/claude_devcontainer/claude/mcp-servers.json
cp /workdir/dotfiles_statox/claude/plugins.json /workdir/claude_devcontainer/claude/plugins.json
cp /workdir/dotfiles_statox/claude/statusline-command.sh /workdir/claude_devcontainer/claude/statusline-command.sh
cp /workdir/dotfiles_statox/claude/skills/repo-onboarding/SKILL.md /workdir/claude_devcontainer/claude/skills/repo-onboarding/SKILL.md
cp /workdir/dotfiles_statox/claude/skills/repo-onboarding/REPO_OVERVIEW_template.md /workdir/claude_devcontainer/claude/skills/repo-onboarding/REPO_OVERVIEW_template.md

chmod +x /workdir/claude_devcontainer/claude/bell-notify.sh /workdir/claude_devcontainer/claude/statusline-command.sh
```

- [ ] **Step 2: Copy CLAUDE.md with the title change**

```markdown
# Default Global Rules (Active Everywhere)

## Communication Style
- Be concise. No long preambles.
- Lead with the answer, then explain.
- When uncertain, say so.
- Use spaced hyphens - instead of em dashes.

## User-Facing Copy
When a task requires writing text that will be read by end users (UI labels, emails, notifications, marketing copy, help text, onboarding messages, etc.), do NOT write the final copy. Instead:
1. Insert a concise placeholder prefixed with `TODO` describing what the copy should convey (e.g. `TODO: welcome message explaining the 3 key benefits`).
2. After completing the task, list every placeholder created so the user knows what copy still needs to be written.

Do NOT use placeholders for internal content (code comments, technical docs, README files, console output).

## Coding & Workflow
- Prefer TypeScript, functional patterns, and test-driven development.
- Plan significant changes and wait for approval.
- Run lint/tests before completion.
- Never auto-commit: only commit on explicit instruction.
- State and run verification for all code changes.
- After writing or modifying code, check for available validation scripts (e.g. `lint`, `format`, `check`, `build` in `package.json` or equivalent) and run them. Fix any errors before reporting the task as complete.
- Prefer POSIX shell tools (jq, awk, sed, grep, find) over throwaway Python scripts for one-off data manipulation. Use `jq` for JSON processing.
- For one-shot tool execution, prefer `uv run <tool>` (Python) and `npx <tool>` (JavaScript) over system-wide or user-wide installs.

## Superpowers
- The superpowers skills should be available. Warn the user if they are not.
- When a superpower tries to create documents never use `docs/superpowers` instead use `superpowers/` directly because `docs/` is often used for temporary build directories
```

Write this to `/workdir/claude_devcontainer/claude/CLAUDE.md`. (Only change from source: line 1 title, "Personal" → "Default". Every other line identical.)

- [ ] **Step 3: Validate**

Run:
```bash
diff /workdir/dotfiles_statox/claude/settings.json /workdir/claude_devcontainer/claude/settings.json
diff /workdir/dotfiles_statox/claude/bell-notify.sh /workdir/claude_devcontainer/claude/bell-notify.sh
diff /workdir/dotfiles_statox/claude/mcp-servers.json /workdir/claude_devcontainer/claude/mcp-servers.json
diff /workdir/dotfiles_statox/claude/plugins.json /workdir/claude_devcontainer/claude/plugins.json
diff /workdir/dotfiles_statox/claude/statusline-command.sh /workdir/claude_devcontainer/claude/statusline-command.sh
diff /workdir/dotfiles_statox/claude/skills/repo-onboarding/SKILL.md /workdir/claude_devcontainer/claude/skills/repo-onboarding/SKILL.md
diff /workdir/dotfiles_statox/claude/skills/repo-onboarding/REPO_OVERVIEW_template.md /workdir/claude_devcontainer/claude/skills/repo-onboarding/REPO_OVERVIEW_template.md
cmp /workdir/dotfiles_statox/claude/bell.wav /workdir/claude_devcontainer/claude/bell.wav
diff /workdir/dotfiles_statox/claude/CLAUDE.md /workdir/claude_devcontainer/claude/CLAUDE.md

jq empty /workdir/claude_devcontainer/claude/settings.json
jq empty /workdir/claude_devcontainer/claude/mcp-servers.json
jq empty /workdir/claude_devcontainer/claude/plugins.json
shellcheck /workdir/claude_devcontainer/claude/bell-notify.sh
shellcheck /workdir/claude_devcontainer/claude/statusline-command.sh
```
Expected: every `diff`/`cmp` on the plain-copy files produces no output; the `CLAUDE.md` diff shows exactly one changed line (the title); both `jq empty` calls and both `shellcheck` calls report no errors.

- [ ] **Step 4: Commit**

```bash
cd /workdir/claude_devcontainer
git add claude/
git commit -m "Add claude/ default configuration"
```

---

### Task 10: README.md

**Files:**
- Create: `/workdir/claude_devcontainer/README.md`

**Interfaces:**
- Consumes: the full picture from Tasks 1-9 (documents the finished repo).

- [ ] **Step 1: Write README.md**

```markdown
# claude_devcontainer

A per-repo development container for running Claude Code, with a small
always-on "broker" container that gives it a safe, narrow path to host
resources.

## Goals

- **Per-repo agent container.** Every repo gets its own container (`agent`),
  scoped to that repo's workspace folder, so Claude only ever sees the path
  it was started in — not the rest of the host filesystem.
- **A broker for host access.** The `agent` container has no direct access
  to the host. Anything it needs from the host goes through `broker`, a
  separate, minimal, global-singleton container (one broker for all
  workspaces), reached over a Unix socket shared via a Docker volume.
  - **Today:** the broker forwards desktop notifications (sound +
    `notify-send`) so Claude can nudge you when it needs input or finishes a
    task, without the agent container needing PulseAudio/D-Bus access
    itself. **This requires a Linux host with a running PulseAudio + D-Bus
    session** — see "Limitations" below.
- **MCP servers, each isolated in its own container.** Rather than running
  as local subprocesses of the agent, MCP servers run in their own singleton
  containers (e.g. `mcp-everything`), reached directly over a dedicated
  Docker network — no broker involvement, since these servers don't hold
  host-facing credentials the way the notification broker does.
- **One command to get in.** `ccc` wraps the whole flow — bring up the
  broker, bring up/reuse the per-repo agent container, drop you into a shell
  in it — so day-to-day use is just `cd <repo> && ccc`.
- **Devcontainer features for the dev environment, the agent Dockerfile for
  the rest.** Standard tooling (GitHub CLI, `uv`, Node, the `claude` binary
  itself) is installed via devcontainer features in `devcontainer.json`.
  Anything without a feature (e.g. `vim`, `ripgrep`, `glab`) is installed
  directly in `agent/Dockerfile` instead.
- **A default Claude Code configuration, shared across every repo.**
  `claude/` holds a starter `CLAUDE.md`, `settings.json`, hooks, and
  statusline script, symlinked into every agent container so they're
  consistent everywhere and edit-in-place from the host. It's opinionated —
  edit or replace it freely.

## Setup

1. Clone this repo anywhere, e.g.:
   ```sh
   git clone <this-repo-url> ~/claude_devcontainer
   ```
2. Add these two lines to your shell rc file (`~/.bashrc`, `~/.zshrc`):
   ```sh
   export CLAUDE_DEVCONTAINER_HOME="$HOME/claude_devcontainer"
   source "$CLAUDE_DEVCONTAINER_HOME/shell-init.sh"
   ```
3. Open a new shell (or `source` your rc file). This defines the `ccc`,
   `ccc-code`, `ccc-compose`, and `ccc-rebuild` commands.

Requires: Docker with Compose v2, `npx` (Node.js), and — for notifications —
a Linux host with PulseAudio and D-Bus running in the user session.

## Architecture

```
host
├── $CLAUDE_DEVCONTAINER_HOME/         <- this repo, cloned anywhere
│   ├── shell-init.sh                  <- defines ccc/ccc-code/ccc-compose/ccc-rebuild aliases
│   ├── devcontainer/
│   │   ├── devcontainer.json          <- agent container config (per-repo instance)
│   │   ├── docker-compose.yml         <- singleton services: broker + mcp-everything (global, all workspaces)
│   │   ├── agent/
│   │   │   ├── Dockerfile             <- agent image: bash, git, vim, ripgrep, gh, glab, ...
│   │   │   └── postCreate.sh          <- symlinks claude/* into ~/.claude on create
│   │   ├── broker/
│   │   │   ├── Dockerfile             <- broker image: socat, dbus, libnotify-bin, pulseaudio-utils
│   │   │   └── handle-notify.sh       <- runs inside broker; plays sound + notify-send per message
│   │   ├── mcp-everything/
│   │   │   └── Dockerfile             <- MCP test server image: node, socat, @modelcontextprotocol/server-everything
│   │   └── scripts/
│   │       ├── ccc                    <- up broker+mcp, up/exec agent
│   │       ├── ccc-code                <- up broker+mcp/agent, open VS Code attached
│   │       ├── ccc-compose             <- thin `docker compose` wrapper for the singleton services project
│   │       └── ccc-rebuild             <- force a clean rebuild of the agent image/container
│   └── claude/                        <- default Claude Code config, symlinked into every agent container
│
├── <repo>/.venv-claude/               <- per-repo bind mount target for the agent's /workdir/.venv
│
├── docker volumes
│   ├── claude-home    <- ~/.claude inside agent containers (session state, persists across repos)
│   ├── glab-config    <- ~/.config/glab-cli inside agent containers
│   ├── vscode-server  <- ~/.vscode-server inside agent containers (VS Code Server + extensions)
│   └── broker-sock    <- /run/broker inside both agent and broker (the notify socket lives here)
│
└── docker networks
    └── mcp-net        <- bridge network joining the agent container and mcp-* singleton containers
```

**Two containers, two lifecycles:**

- `broker` is a **global singleton** — one instance total, shared by every
  repo's agent container, started via `docker compose` (`docker-compose.yml`,
  shared with `mcp-everything`) and left running (`restart: unless-stopped`).
  It's the only container with host-facing access (`network_mode: host`, the
  host's PulseAudio/D-Bus sockets bind-mounted in, `apparmor:unconfined`
  because Ubuntu's AppArmor D-Bus mediation blocks the session bus
  otherwise). Its whole job is to sit on `UNIX-LISTEN:/run/broker/notify.sock`
  (via `socat`) and run `handle-notify.sh` for each connection.
- `agent` is **per-repo** — one instance per workspace folder, built from
  `agent/Dockerfile`, created/reused by the `devcontainers` CLI
  (`devcontainer.json`). It mounts the repo at `/workdir`, gets `broker-sock`
  so it can reach the broker's socket, and joins the `mcp-net` bridge network
  so it can reach singleton MCP server containers (e.g. `mcp-everything`) by
  service name — but never touches the host directly.

**Notification flow (today's only broker traffic):** a Claude Code hook in
the agent container runs `bell-notify.sh <type> <message>`, which pipes
`type|message` into `UNIX-CONNECT:/run/broker/notify.sock`. The broker's
`socat` forks a handler running `handle-notify.sh`, which plays `bell.wav`
and fires a `notify-send` desktop notification on the host, detached via
`setsid` so the D-Bus round-trip survives `socat` tearing down the
connection handler as soon as the client disconnects.

**MCP servers:** each MCP server runs in its own container, alongside the
broker, as a singleton service in `docker-compose.yml` (e.g.
`mcp-everything`, wrapping `@modelcontextprotocol/server-everything`). The
agent container reaches them directly over the `mcp-net` bridge network by
service name. Each server's container wraps its stdio-based process behind
`socat TCP-LISTEN:<port>,fork`, and Claude Code is configured to reach it
with `nc <service-name> <port>` as the MCP server's `command`.

To add a new MCP server: add a `devcontainer/mcp-<name>/Dockerfile`
following the `mcp-everything` pattern, add a matching service to
`docker-compose.yml` on the `mcp-net` network, and add an entry to
`claude/mcp-servers.json`. `postCreate.sh` merges that file's contents into
the `mcpServers` key of `~/.claude.json` on every container creation, via
`jq`, without disturbing the rest of that file's content — `~/.claude.json`
itself stays untracked, while the MCP server list stays under version
control.

**Claude Code plugins:** required plugins (and the marketplaces they come
from) are declared in `claude/plugins.json`, e.g.:
```json
{
  "marketplaces": ["anthropics/claude-plugins-official"],
  "plugins": ["skill-creator@claude-plugins-official"]
}
```
`postCreate.sh` reads this file on every container creation and, for
anything not already present, runs `claude plugin marketplace add <source>`
/ `claude plugin install <name>@<marketplace> --scope user` — idempotent, so
re-running is a no-op except for entries added since the last container
creation. Installing a plugin doesn't enable it: also add
`"<name>@<marketplace>": true` to `enabledPlugins` in `claude/settings.json`.
To add a new plugin: find its `name@marketplace` id (`claude plugin list
--available --json` inside a container, once the marketplace is added), add
it to `plugins.json`, add the matching `enabledPlugins` entry, then
`ccc-rebuild` (or just recreate the container) to pick it up.

**Exception — the `typescript` MCP server runs in-process, not as a
container.** Unlike `mcp-everything`, a language server needs to see the
actual repo checked out in *this* workspace's agent container, which a
global singleton container never has mounted. So instead of a
`docker-compose.yml` service, `agent/Dockerfile` builds
[`mcp-language-server`](https://github.com/isaacphi/mcp-language-server) (a
Go binary, in an isolated builder stage so it doesn't depend on the node
feature) and `postCreate.sh` installs `typescript-language-server` via npm
once Node is available. Claude Code spawns it directly as a local stdio
process — `command: mcp-language-server`, pointed at `/workdir` — no `nc`,
no `mcp-net`. This is the pattern to follow for any other MCP server that
needs filesystem access to the repo rather than being a stateless shared
service.

**Extensibility seam for per-repo customization (not built yet):**
`devcontainer.json`'s `dockerComposeFile` field accepts an array of compose
files merged in order, so a repo can later append its own
`.devcontainer/compose.override.yml` without any change to this base setup.

## Claude Code default configuration (`claude/`)

`claude/` holds a default Claude Code configuration, independent of this
devcontainer setup and shared with any bare-host (non-container) use of
Claude Code too:

- `CLAUDE.md` — global instructions, active in every project.
- `settings.json` — permissions, hooks (wired to `bell-notify.sh`),
  statusline, theme, and other Claude Code settings.
- `bell-notify.sh` / `bell.wav` — the client half of the notification flow
  described above; invoked by the `Notification`/`Stop` hooks in
  `settings.json`.
- `statusline-command.sh` — the statusline script referenced by
  `settings.json`.
- `mcp-servers.json` — the `mcpServers` config (user scope), tracked here
  instead of directly in `~/.claude.json` since that file accumulates other
  session/project state you don't want versioned; see "MCP servers" above.
- `plugins.json` — required plugins and their marketplaces, installed by
  `postCreate.sh`; see "Claude Code plugins" above.
- `skills/` — Claude Code skills, one subdirectory per skill (e.g.
  `skills/repo-onboarding/SKILL.md`), in the layout Claude Code expects for
  personal skills. Symlinked as a whole directory into `~/.claude/skills`
  like every other entry here; unlike plain files, though, `postCreate.sh`
  first deletes `~/.claude/skills` if it exists as a real (non-symlink)
  directory — e.g. left over from a skill created directly inside a
  container before this existed — so this repo's version always wins and no
  manual reconciliation is needed.

This is opinionated starter config — edit, trim, or replace it for your own
use.

`agent/postCreate.sh` symlinks every file under `claude/` into `~/.claude`
(a named volume, `claude-home`) inside the agent container, on every
container creation, and separately merges `mcp-servers.json`'s contents into
the `mcpServers` key of `~/.claude.json` via `jq`. So editing a file under
`claude/` on the host takes effect the next time a container is created or
recreated — no rebuild needed, and no copy to keep in sync since it's a
symlink both ways.

## Using it: getting the CLI running

1. `cd` into the repo you want to work on.
2. Run `ccc`.

That single command:
- brings up the global `broker` singleton if it isn't already running
  (`docker compose ... up -d --wait`);
- creates (or reuses) the `agent` container for the current workspace folder
  via `devcontainers/cli up`;
- execs a `bash` shell inside it (`devcontainers/cli exec`).

From that shell, run `claude` (the actual Claude Code binary — installed via
the `claude-code` devcontainer feature) as usual. Inside the container you
have your repo at `/workdir`, this repo's config at `~/.claude-devcontainer`,
`gh`/`glab` for GitHub/GitLab, and desktop notifications working through the
broker.

To just inspect/manage the broker without going through the full flow:
```
ccc-compose ps
ccc-compose logs -f
ccc-compose down
```

## Using it: the VS Code Claude Code extension

VS Code's Claude Code extension can run confined inside the same `agent`
container the CLI uses, instead of on the bare host. Rather than the usual
"Reopen in Container" flow (which expects a `.devcontainer/devcontainer.json`
inside the repo), VS Code **attaches** to the container that the CLI flow
above already creates — no changes to the repo, no separate container.

1. `cd` into the repo you want to work on.
2. Run `ccc-code`.

That single command brings up the broker and the `agent` container exactly
like `ccc` does, then opens VS Code already attached to that container with
`/workdir` open. The Claude Code extension (`anthropic.claude-code`)
installs itself automatically the first time VS Code connects — listed
under `customizations.vscode.extensions` in `devcontainer.json`. It persists
across container recreation via the `vscode-server` volume, so it won't
reinstall on every rebuild. It runs remotely inside the container, so it's
exactly as confined as the CLI.

Adding/removing extensions this way only takes effect on containers created
*after* the change — run `ccc-rebuild` once to pick it up on an existing
container.

`ccc-code` opens VS Code via an **undocumented VS Code URI scheme**
(`vscode-remote://attached-container+<hex>`), so it could break on a future
VS Code update. If it does, the fallback is fully manual and doesn't depend
on the script at all: run `ccc` (or just `ccc-code`, ignoring its own
failure) to make sure the container is up, then in VS Code use Command
Palette → **Dev Containers: Attach to Running Container…** → pick the repo's
container → **File → Open Folder** → `/workdir`.

Running `ccc-code` more than once against the same repo doesn't create a
second container — `devcontainers/cli up` reuses the existing one (same as
`ccc`), and VS Code supports multiple windows attached to the same container
concurrently.

## Updating the setup

**Adding a new tool — features vs. `agent/Dockerfile`.** Prefer a
devcontainer feature when one exists for the tool (check
[containers.dev/features](https://containers.dev/features)) — that's how
GitHub CLI, `uv`, Node, and the `claude` binary itself are installed today.
Fall back to adding it to `agent/Dockerfile` only when no feature exists.

**Add a devcontainer feature** (e.g. a new language runtime): edit the
`features` block in `devcontainer.json`, then rebuild (see below). Run `npx
@devcontainers/cli up ...` once normally afterwards to refresh
`devcontainer-lock.json` (feature version/integrity pins) — commit that file
alongside the `devcontainer.json` change.

**Add a tool to the agent image** (when no feature exists for it): edit
`agent/Dockerfile`, then rebuild.

**Change the broker** (new notification behavior): edit `broker/Dockerfile`
or `broker/handle-notify.sh`, then recreate just that service:
```
ccc-compose up -d --build --force-recreate broker
```

**Change an MCP server** (new server, dependency bump): edit
`mcp-<name>/Dockerfile` or `docker-compose.yml`, then recreate just that
service:
```
ccc-compose up -d --build --force-recreate mcp-everything
```

**Rebuild the agent container from scratch** (picks up Dockerfile/feature
changes that a plain `ccc` run won't, since that reuses the existing
container): from the repo you want to rebuild,
```
ccc-rebuild
```
This removes the existing container and rebuilds the image, then drops you
into a shell in the fresh container. Run it once per repo whose agent
container needs the update (each repo has its own container instance).

**Add a required Claude Code plugin**: add its `name@marketplace` id to
`plugins.json` (adding the marketplace source too if it's new), add
`"<name>@<marketplace>": true` under `enabledPlugins` in `settings.json`,
then recreate the container (`ccc` or `ccc-rebuild`).

**Change what gets symlinked into `~/.claude`** (settings, hooks, statusline
script, skills, etc.): edit the files under `claude/`, including
adding/editing skills under `claude/skills/<name>/SKILL.md`. They're
re-symlinked into the `claude-home` volume by `agent/postCreate.sh` on every
container creation, so a plain `ccc` (which recreates the container if
needed) or `ccc-rebuild` picks them up — no separate step required.

## Limitations / TODOs

### Notifications are Linux-only

The `broker` container assumes a Linux host with a running PulseAudio +
D-Bus user session (`network_mode: host`, `apparmor:unconfined`,
`/run/user/$UID` bind-mounted in). It won't work as-is on macOS or a
headless/WSL host with no desktop session.

**TODO:** rename the `broker` service to something like
`linux-desktop-notifications` and make bringing it up opt-in via a setting,
so the rest of the setup (agent container, MCP servers) degrades gracefully
on hosts without a Linux desktop session, instead of `ccc` unconditionally
trying to start it.

### Long build time

The rebuild time can get fairly long:

- The agent image is built from `agent/Dockerfile`, then the devcontainers
  CLI layers the features from `devcontainer.json` on top.
- A simple change to the base image or to `postCreate.sh` triggers a full
  rebuild, which is slow because the feature layers get rebuilt too.

This is normal devcontainer behavior but can get annoying when iterating on
this setup.

**Tried and rejected: a local devcontainer feature.** The plan was to move
`postCreate.sh` and the extra apt packages into a local devcontainer
feature, pinned to install last via `overrideFeatureInstallOrder`, so
editing them would only rebuild that one feature's layer. This doesn't work
with this setup's architecture: the devcontainers CLI resolves local
feature paths against the `.devcontainer/` folder inside the **workspace
folder** (whichever repo you `cd`'d into), not against the directory
holding `devcontainer.json` (`$CLAUDE_DEVCONTAINER_HOME/devcontainer`,
deliberately outside every target repo). Those are different directories by
design — that's exactly what lets one shared config work across every repo
without writing anything into them. Local features fundamentally require
the opposite (config and workspace collocated under one `.devcontainer/`
folder), so the build fails with `Local file path parse error. Resolved
path must be a child of the .devcontainer/ folder.` regardless of how the
feature paths are written. There's no flag or path trick around it; see
[microsoft/vscode-remote-release#11356](https://github.com/microsoft/vscode-remote-release/issues/11356).

**Also considered: a base-image split.** Build a separate "base" image
containing just the upstream features, tag it, then have `agent/Dockerfile`
do `FROM` that tag plus the apt packages and `postCreate.sh` on top, with
`features` removed from the main `devcontainer.json`. This would give real
cache separation for both, but requires a second build pipeline (its own
`devcontainer.json`, a manual build/tag step, remembering to redo it on
every feature/package bump) for a problem that's mostly caused by one file.
Set aside for now in favor of keeping the setup as one self-contained
config; worth revisiting if the rebuild time becomes a bigger problem than
the added maintenance.

## License

MIT — see [LICENSE](LICENSE).
```

Write this to `/workdir/claude_devcontainer/README.md`.

- [ ] **Step 2: Confirm no "dotfiles" mentions and check key command names appear**

Run:
```bash
grep -i dotfiles /workdir/claude_devcontainer/README.md
grep -c '`ccc`' /workdir/claude_devcontainer/README.md
```
Expected: `grep -i dotfiles` produces no output (exits 1); the `ccc` count is greater than 0.

- [ ] **Step 3: Commit**

```bash
cd /workdir/claude_devcontainer
git add README.md
git commit -m "Add README"
```

---

### Task 11: Repo-wide validation pass

**Files:** none created; validates everything from Tasks 1-10.

**Interfaces:** none.

- [ ] **Step 1: Grep the whole repo for "dotfiles" (case-insensitive)**

Run: `grep -ril dotfiles /workdir/claude_devcontainer --exclude-dir=.git --exclude-dir=superpowers`
Expected: no output (exits 1). (`superpowers/` is excluded because the spec document legitimately discusses the source `dotfiles_statox` repo by name as historical context — that's fine, it's not part of the shipped product.)

- [ ] **Step 2: Grep for the old command names to confirm none were missed**

Run: `grep -rl 'claude-devcontainer\|code-devcontainer' /workdir/claude_devcontainer --exclude-dir=.git --exclude-dir=superpowers`
Expected: no output (exits 1).

- [ ] **Step 3: Validate every JSON file parses**

Run:
```bash
find /workdir/claude_devcontainer -name '*.json' -not -path '*/.git/*' -print0 | xargs -0 -n1 jq empty
```
Expected: no output, exit code 0 for every file (xargs propagates the first non-zero exit; re-run individually if it fails to see which file).

- [ ] **Step 4: Shellcheck every shell script**

Run:
```bash
find /workdir/claude_devcontainer -name '*.sh' -not -path '*/.git/*' -print0 | xargs -0 shellcheck
shellcheck /workdir/claude_devcontainer/devcontainer/scripts/ccc \
           /workdir/claude_devcontainer/devcontainer/scripts/ccc-compose \
           /workdir/claude_devcontainer/devcontainer/scripts/ccc-rebuild \
           /workdir/claude_devcontainer/devcontainer/scripts/ccc-code
```
Expected: no errors reported.

- [ ] **Step 5: Confirm the four scripts and shell-init.sh are executable**

Run: `ls -l /workdir/claude_devcontainer/devcontainer/scripts/ /workdir/claude_devcontainer/claude/bell-notify.sh /workdir/claude_devcontainer/claude/statusline-command.sh /workdir/claude_devcontainer/devcontainer/broker/handle-notify.sh /workdir/claude_devcontainer/devcontainer/agent/postCreate.sh`
Expected: every listed file's permissions include `x` (e.g. `-rwxr-xr-x`).

- [ ] **Step 6: Fix anything the checks above surfaced, then commit if any fixes were needed**

If Steps 1-5 all passed cleanly, skip committing (nothing changed). Otherwise:
```bash
cd /workdir/claude_devcontainer
git add -A
git commit -m "Fix issues found by repo-wide validation"
```

---

### Task 12: Manual end-to-end verification (USER ACTION REQUIRED — Docker)

**Files:** none created.

**Interfaces:** exercises the full stack built in Tasks 1-11.

I don't have Docker, `npx`, or the `devcontainers` CLI available in my environment, so I cannot run this task myself. Please run the following on your machine and tell me the output (or paste any errors) so we can fix anything that comes up.

- [ ] **Step 1: Point the env var at your local clone and source shell-init.sh**

```sh
export CLAUDE_DEVCONTAINER_HOME=/workdir/claude_devcontainer
source "$CLAUDE_DEVCONTAINER_HOME/shell-init.sh"
type ccc ccc-compose ccc-rebuild ccc-code
```
Expected: `type` prints all four as aliases pointing at
`$CLAUDE_DEVCONTAINER_HOME/devcontainer/scripts/...`.

- [ ] **Step 2: Validate the compose file**

```sh
export DEV_UID
DEV_UID="$(id -u)"
docker compose -f "$CLAUDE_DEVCONTAINER_HOME/devcontainer/docker-compose.yml" config
```
Expected: prints the fully-resolved compose config with no errors, and
`${CLAUDE_DEVCONTAINER_HOME}/claude` resolved to your actual clone path in
the `broker` service's volumes.

- [ ] **Step 3: Bring up the singleton services**

```sh
ccc-compose up -d --wait
ccc-compose ps
```
Expected: `broker` and `mcp-everything` both show as `running`/healthy.
Report back if either fails to build or start.

- [ ] **Step 4: Enter the agent container from a scratch test repo**

```sh
mkdir -p /tmp/ccc-test-repo && cd /tmp/ccc-test-repo && git init -q
ccc
```
Expected: builds the agent image (first run only, will take a while), then
drops you into a `bash` shell inside the container with `/workdir` as the
current directory. Report back if the build or `devcontainers/cli up` fails.

- [ ] **Step 5: Inside the container, confirm the claude/ config was symlinked in**

Run inside the container shell from Step 4:
```sh
ls -la ~/.claude
cat ~/.claude/CLAUDE.md | head -1
```
Expected: `~/.claude/CLAUDE.md`, `settings.json`, `bell-notify.sh`, etc. are
symlinks pointing into `/home/dev/.claude-devcontainer/claude/...`; the
first line of `CLAUDE.md` reads `# Default Global Rules (Active Everywhere)`.

- [ ] **Step 6: Confirm the real `claude` CLI is on PATH inside the container**

Run inside the container: `claude --version`
Expected: prints a version string (confirms the `claude-code` devcontainer
feature installed correctly and that `ccc` didn't accidentally shadow it).

- [ ] **Step 7: Trigger a notification end-to-end**

Run inside the container:
```sh
bash ~/.claude/bell-notify.sh done "test notification"
```
Expected: on the host, you hear `bell.wav` play and see a desktop
notification titled "test notification". Report back if nothing happens —
check `ccc-compose logs broker` for the `[broker] notify:` log line to
narrow down whether the message reached the broker at all.

- [ ] **Step 8: Exit and clean up the scratch test repo**

```sh
exit   # leave the container shell
rm -rf /tmp/ccc-test-repo
```

Once you've run through Steps 1-7 and confirmed each "Expected" outcome (or
told me what broke), this plan is complete.

---

## Self-Review Notes

- **Spec coverage:** every section of the design doc (`superpowers/specs/2026-07-17-claude-devcontainer-export-design.md`) maps to a task — layout (Tasks 1-10), `CLAUDE_DEVCONTAINER_HOME` (Tasks 5-8), command renaming (Task 7-8), nvm workaround removal (Task 7), CLAUDE.md heading (Task 9), broker TODO note (Task 10), MIT license (Task 1), verification approach (Task 12).
- **No placeholders:** every step above contains the literal file content to write or the literal command to run; none defer to "similar to Task N" or "add appropriate X".
- **Type/name consistency:** `CLAUDE_DEVCONTAINER_HOME` is spelled identically everywhere it's used (devcontainer.json, docker-compose.yml, all four scripts, shell-init.sh, README); `REPO_CLAUDE` (postCreate.sh) and `/home/dev/.claude-devcontainer` (devcontainer.json mount target) are the two ends of the same mount and match; script names `ccc`/`ccc-compose`/`ccc-rebuild`/`ccc-code` match across scripts, shell-init.sh, and README.
