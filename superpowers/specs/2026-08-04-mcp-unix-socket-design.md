# MCP container communication over unix sockets — design

## Goal

Replace TCP-over-docker-network communication between the agent devcontainer and MCP
server containers with unix sockets shared via named volumes, matching the pattern
`claude-desktop-notification` already uses. This removes the need for the agent to be
attached to any docker network at all, and establishes a reusable convention for future
MCP containers.

## Scope

- Migrate the existing `mcp-context7` container from TCP (`mcp-net` + port 3002) to a
  unix socket.
- Retire the `mcp-net` docker network entirely (both compose files, and the agent's
  `--network=mcp-net` runArg).
- Establish a general convention so any MCP container added later follows the same
  pattern without new design work.
- Tighten socket permissions on both the new MCP socket and the existing
  `claude-desktop-notification` socket (currently `mode=777`) to a consistent,
  least-privilege model.

Out of scope: changes to the `mcp-language-server`-based servers (`typescript`,
`python`), which run as in-container stdio processes and never talk to a separate
container.

## Convention for MCP-over-socket containers

For an MCP server container named `<name>`:

- A named Docker volume `<name>-sock`, mounted at `/run/<name>` in both that container
  and the agent devcontainer.
- The server listens with `socat UNIX-LISTEN:/run/<name>/mcp.sock,mode=660,fork,unlink-early
  EXEC:<the actual mcp stdio process>`.
- The agent reaches it via a `claude/mcp-servers.json` entry:
  ```json
  {
    "<name>": {
      "command": "socat",
      "args": ["-", "UNIX-CONNECT:/run/<name>/mcp.sock,retry=10,interval=1"]
    }
  }
  ```
- The container and the agent run as the same UID/GID (`DEV_UID`/`DEV_GID`, already
  exported by `scripts/lib/env.sh`), so the socket can be `mode=660` (owner+group
  read/write) rather than world-accessible.

No docker network is needed for any of this — communication happens entirely over the
mounted volume.

## Why `socat` with retry, not `nc -U`

`ccc` starts the singleton compose services before the agent devcontainer (`docker
compose up --wait`, or no wait at all under podman-compose). `--wait` only waits for
"container running," not "socket file created and chmod'd" — and podman-compose waits
for neither. `socat`'s `retry=10,interval=1` on the client side absorbs that startup
race instead of the agent's first MCP call failing outright. `nc -U` has no equivalent
retry/backoff and would fail immediately if the socket isn't there yet. This also keeps
one tool (`socat`) as the convention for all unix-socket communication in the repo,
matching the existing listener side and the existing notification client
(`bell-notify.sh`).

## Permissions

- `mcp-context7`: gains `ARG USER_UID`/`USER_GID` build args (mirroring the agent
  Dockerfile), adjusting the image's existing `node` user to that UID/GID rather than
  creating a new user. Socket created at `mode=660`.
- `claude-desktop-notification`: already runs as `user: "${DEV_UID}"` at the compose
  level (no build-time user creation needed there). Its socket's `mode=777` becomes
  `mode=660` for consistency with the new convention — only the matching UID/GID can
  read/write it, not any arbitrary container that happens to mount the volume.

## File-level changes

- **`devcontainer/devcontainer.json`**
  - Remove `runArgs: ["--network=mcp-net"]`.
  - Add mount: `source=mcp-context7-sock,target=/run/mcp-context7,type=volume`.
- **`devcontainer/docker-compose.yml`** and **`devcontainer/docker-compose.podman.yml`**
  - Remove the `mcp-net` network definition and its reference under `mcp-context7`.
  - Add named volume `mcp-context7-sock`.
  - Add `build.args: { USER_UID: "${DEV_UID}", USER_GID: "${DEV_GID}" }` to
    `mcp-context7` (mirrors the agent service already doing this).
  - `docker-compose.yml` only: change `claude-desktop-notification`'s socat `mode=777`
    to `mode=660`.
- **`devcontainer/mcp-context7/Dockerfile`**
  - Drop `EXPOSE 3002`.
  - Add `ARG USER_UID=1000` / `ARG USER_GID=1000`, adjust the existing `node` user/group
    to those IDs.
  - Replace `CMD ["socat", "TCP-LISTEN:3002,fork,reuseaddr", "EXEC:context7-mcp"]` with
    `CMD ["socat", "UNIX-LISTEN:/run/mcp-context7/mcp.sock,mode=660,fork,unlink-early",
    "EXEC:context7-mcp"]`.
- **`devcontainer/claude-desktop-notification/Dockerfile`**
  - Change the existing `CMD`'s `mode=777` to `mode=660`.
- **`claude/mcp-servers.json`**
  - `context7` entry: `{"command": "socat", "args": ["-",
    "UNIX-CONNECT:/run/mcp-context7/mcp.sock,retry=10,interval=1"]}` (was `{"command":
    "nc", "args": ["mcp-context7", "3002"]}`).
- **`claude/CLAUDE.md`**
  - Update the "Host networking" bullet to describe the current setup: the agent
    container has no docker network access; it talks to MCP server containers over
    unix sockets shared via mounted volumes.

## Testing / verification

- `ccc-rebuild` (or manual `docker compose up` + `devcontainer up`) then confirm from
  inside the agent: `ls -l /run/mcp-context7/mcp.sock` shows the expected owner and
  `srw-rw----` mode.
- Exercise a `context7` MCP call (e.g. `resolve-library-id`) from Claude Code and confirm
  it succeeds.
- Confirm `docker network ls` no longer shows `mcp-net` after a full teardown/rebuild.
- Repeat the socket-permission check for `claude-desktop-notification` and confirm a
  notification still fires (e.g. via `bell-notify.sh`).
- Run the same checks under podman (`docker-compose.podman.yml`) to confirm parity.

## Migration notes

This changes volume names and removes a network, so existing running containers need a
full `ccc-compose down` + rebuild (stale `mcp-net`/old volumes won't be cleaned up by a
simple restart). This is a local dev-environment change with no production impact.
