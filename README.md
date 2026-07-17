# claude_devcontainer

A per-repo development container for running Claude Code, with a small
always-on "broker" container that gives it a safe, narrow path to host
resources.

## Requirements

For now the setup has only been tested on linux + docker.

System requirements:

- `docker` (TODO podman)
- `node` + `npx` (TODO use other sources for devcontainer/cli
- If using VSCode: The devcontainer extension

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
