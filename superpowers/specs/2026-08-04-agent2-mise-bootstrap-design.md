# agent2: mise-based devcontainer image (experiment)

## Context

`devcontainer/agent/` is the current devcontainer image. It installs OS
tooling via `apt-get` in the Dockerfile, plus a manual `.deb` download for
`glab`, and installs a couple of language-server binaries in `postCreate.sh`
(deferred there only because node/python arrive later via devcontainer
*features*, after the Dockerfile has already built).

`devcontainer/agent2/` is a new, parallel experiment to see whether
[mise](https://mise.jdx.dev) can replace that apt/curl/postCreate tooling
install with a single declarative config, split correctly between mise's
two install mechanisms:

- `[bootstrap.packages]` — OS packages via apt/apk/brew. Per mise's docs,
  intended for "things that are needed before a project or workstation is
  ready, but that do not belong in [tools]: native libraries, ... one-time
  machine setup."
- `[tools]` — versioned, per-tool installs via mise's various backends
  (core, `npm:`, `pipx:`, `go:`, `aqua:`, etc).

This round adds `agent2` as a new service in `devcontainer/docker-compose.yml`
(already done) but does **not** wire it into `devcontainer.json` or replace
`agent`. Scope is intentionally narrow: get tool/package installation right
via mise. The non-tooling parts of `agent/postCreate.sh` (symlinking
`claude/` config into `~/.claude`, merging `mcp-servers.json`, installing
Claude plugins, bash aliases) are explicitly out of scope for this round —
`agent2` ships no `postCreate.sh`.

## File layout

- `devcontainer/agent2/Dockerfile` — rewritten to install mise, copy in
  `mise.toml`, run `mise bootstrap`, then create the `dev` user.
- `devcontainer/agent2/mise.toml` — new file, copied into the image as
  `$MISE_CONFIG_DIR/config.toml` (`/mise/config.toml`). Single source of
  truth for both bootstrap packages and tools.
- `devcontainer/docker-compose.yml` — no further change; the `agent2`
  service block already exists.

## `mise.toml`

```toml
[bootstrap.packages]
"apt:bash" = "latest"
"apt:jq" = "latest"
"apt:less" = "latest"
"apt:netcat-openbsd" = "latest"
"apt:openssh-client" = "latest"
"apt:ripgrep" = "latest"
"apt:shellcheck" = "latest"
"apt:socat" = "latest"
"apt:vim" = "latest"

[tools]
node = "26"
python = "3.14"
"go:github.com/isaacphi/mcp-language-server" = "latest"
"npm:typescript-language-server" = "latest"
"pipx:pyright" = "latest"
"aqua:gitlab-org/cli" = "latest"
```

Mapping from `agent/Dockerfile` + `agent/postCreate.sh`, and why each tool
landed where it did:

| Tool | agent/ mechanism | agent2/ mechanism | Why |
|---|---|---|---|
| bash, jq, less, netcat-openbsd, openssh-client, ripgrep, shellcheck, socat, vim | apt-get in Dockerfile | `[bootstrap.packages]` (apt) | Plain OS utilities, no project-version meaning — exactly mise's stated bootstrap use case. |
| glab | manual `.deb` download + `apt-get install` of the local file | `[tools]` via `aqua:gitlab-org/cli` | Not in Debian's apt repos, hence the bespoke curl/dpkg dance today. mise's aqua backend carries GitLab CLI, so it becomes a normal versioned tool instead. **Needs a build-time check** that this aqua package name resolves and produces a working `glab` binary. |
| mcp-language-server | `go install` in a separate builder stage, binary copied in | `[tools]` via `go:github.com/isaacphi/mcp-language-server` (already present in agent2 today) | Unchanged — already the right mechanism. |
| typescript-language-server | `npm install -g` in `postCreate.sh`, deferred because node comes from a devcontainer feature layered on after the Dockerfile builds | `[tools]` via `npm:typescript-language-server` | agent2 installs node via mise *inside* the Dockerfile, so there's no ordering problem — no postCreate step needed. |
| pyright | `uv tool install` in `postCreate.sh`, same deferral reason | `[tools]` via `pipx:pyright` | Same reasoning as above. |
| node, python | `mise install --system` + `mise use -g` (two RUN lines each) | `[tools]` entries, installed by `mise bootstrap` | Declaring them in `mise.toml` and running `mise bootstrap` does both the install and the "use" in one step. |

## `Dockerfile` flow

1. `FROM debian:13-slim`; apt-install the minimal prerequisites needed
   before mise can take over: `sudo curl git ca-certificates build-essential`
   (unchanged from today's agent2/Dockerfile).
2. Set `MISE_DATA_DIR`, `MISE_CONFIG_DIR`, `MISE_CACHE_DIR`,
   `MISE_INSTALL_PATH`, `PATH` env vars (unchanged), `curl https://mise.run | sh`.
3. `COPY mise.toml $MISE_CONFIG_DIR/config.toml`.
4. `RUN mise bootstrap --yes` — installs `[bootstrap.packages]` (apt) and
   `[tools]` in one non-interactive step, run as root so both land in the
   shared `/mise` dir. Replaces today's four separate `mise install --system`
   / `mise use -g` lines.
5. Create the `dev` user: `ARG USER_UID=1000`, `ARG USER_GID=1000`,
   `groupadd`/`useradd`, matching `agent/Dockerfile`'s pattern. (The
   `userdel ubuntu` step in `agent/Dockerfile` is specific to the
   `ubuntu:24.04` base image having a pre-existing `ubuntu` user at 1000:1000
   — not needed here since agent2 is based on `debian:13-slim`.)
6. `USER dev`, `WORKDIR /workdir`. No explicit `chown` of `/mise` — mise's
   default umask leaves it world-readable/executable, which is all `dev`
   needs to run the shims.

## Testing / verification

- `docker compose -f devcontainer/docker-compose.yml build agent2` (run by
  the user — this environment has no docker access).
- Exec into the running container as `dev` and check: `node --version`,
  `python --version`, `glab --version`, `mcp-language-server` (runs/prints
  usage), `typescript-language-server --version`, `pyright --version`, and a
  couple of the apt-bootstrapped binaries (`jq --version`, `rg --version`,
  `shellcheck --version`).
- Confirm `mise bootstrap --yes` is idempotent on a rebuild (no prompts, no
  errors), matching the "CI usage" pattern from mise's docs.

## Known risks / open questions

- The `aqua:gitlab-org/cli` package name for `glab` is unverified — needs
  confirming during implementation that it resolves in the aqua registry and
  produces a working binary. If it doesn't exist under that name, fall back
  to keeping glab's manual `.deb` install in the Dockerfile (outside mise)
  rather than forcing it into `[bootstrap.packages]`, since apt/apk/brew
  package managers don't support arbitrary URL-sourced `.deb` files.
- Out of scope for this round: `postCreate.sh` equivalent (claude config
  symlinks, mcp-servers.json merge, plugin install, bash aliases), and
  wiring `agent2` into `devcontainer.json` to actually replace `agent`.
