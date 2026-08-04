# agent2 mise-bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite `devcontainer/agent2/Dockerfile` to install all OS packages and dev tools via mise, split correctly between `[bootstrap.packages]` (apt) and `[tools]` (versioned backends), matching the design in `superpowers/specs/2026-08-04-agent2-mise-bootstrap-design.md`.

**Architecture:** A new `devcontainer/agent2/mise.toml` becomes mise's global config (`$MISE_CONFIG_DIR/config.toml`), declaring `[bootstrap.packages]` for plain OS utilities and `[tools]` for node/python/glab/mcp-language-server/typescript-language-server/pyright. The Dockerfile installs mise, copies in `mise.toml`, runs `mise bootstrap --yes` once as root, then creates a `dev` user matching `agent/Dockerfile`'s UID/GID pattern.

**Tech Stack:** Docker, Debian 13-slim, mise (jdx/mise), apt, aqua/npm/pipx/go mise backends.

## Global Constraints

- No docker access in this environment (per user's CLAUDE.md) — every build/run/exec step in this plan is a request for the user to run a command on the host and report back the output; do not attempt to invoke `docker`/`docker compose` directly.
- Do not wire `agent2` into `devcontainer.json` or replace `agent` — out of scope this round (per spec).
- Do not port `postCreate.sh` logic (claude config symlinks, mcp merge, plugin install, aliases) — out of scope this round (per spec).
- `agent2` must remain listed in `devcontainer/docker-compose.yml` (already present, no change needed there).
- Tool versions must match today's `agent2/Dockerfile`: `node = "26"`, `python = "3.14"`.
- `USER_UID`/`USER_GID` build args must default to `1000`/`1000`, matching `agent/Dockerfile`.

---

### Task 1: Write `devcontainer/agent2/mise.toml`

**Files:**
- Create: `devcontainer/agent2/mise.toml`

**Interfaces:**
- Produces: a TOML file with top-level tables `[bootstrap.packages]` and `[tools]`, consumed by Task 2's `COPY` instruction and by `mise bootstrap --yes` at image build time.

- [ ] **Step 1: Create the file**

Write `devcontainer/agent2/mise.toml` with exactly this content:

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

- [ ] **Step 2: Validate TOML syntax**

Run: `python3 -c "import tomllib,sys; tomllib.load(open('devcontainer/agent2/mise.toml','rb')); print('ok')"`
Expected: `ok`

(If `tomllib` isn't available — Python < 3.11 — use `uv run --with tomli python3 -c "import tomli; tomli.load(open('devcontainer/agent2/mise.toml','rb')); print('ok')"` instead.)

- [ ] **Step 3: Commit**

```bash
git add devcontainer/agent2/mise.toml
git commit -m "Add mise.toml for agent2 devcontainer bootstrap/tools split"
```

---

### Task 2: Rewrite `devcontainer/agent2/Dockerfile`

**Files:**
- Modify: `devcontainer/agent2/Dockerfile` (full rewrite)

**Interfaces:**
- Consumes: `devcontainer/agent2/mise.toml` from Task 1 (copied in as `$MISE_CONFIG_DIR/config.toml`).
- Produces: an image where `mise bootstrap --yes` has installed both the apt packages and the `[tools]` entries system-wide under `/mise`, and a non-root `dev` user (UID/GID configurable via build args) with `/workdir` as its home working directory.

- [ ] **Step 1: Replace the Dockerfile contents**

Write `devcontainer/agent2/Dockerfile` with exactly this content:

```dockerfile
FROM debian:13-slim

RUN apt-get update  \
    && apt-get -y --no-install-recommends install  \
        sudo curl git ca-certificates build-essential \
    && rm -rf /var/lib/apt/lists/*

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV MISE_DATA_DIR="/mise"
ENV MISE_CONFIG_DIR="/mise"
ENV MISE_CACHE_DIR="/mise/cache"
ENV MISE_INSTALL_PATH="/usr/local/bin/mise"
ENV PATH="/mise/shims:$PATH"
# ENV MISE_VERSION="..."

RUN curl https://mise.run | sh

COPY mise.toml /mise/config.toml
RUN mise bootstrap --yes

# Create dev user with UID/GID matching the host user, passed in as build
# args (see scripts/lib/env.sh + devcontainer.json's build.args). This
# matters on macOS, where the default host user UID (501) differs from the
# Dockerfile's old hardcoded UID (1000).
ARG USER_UID=1000
ARG USER_GID=1000
RUN (getent group "$USER_GID" >/dev/null || groupadd -g "$USER_GID" dev) \
    && useradd -m -s /bin/bash -u "$USER_UID" -g "$USER_GID" dev

USER dev
WORKDIR /workdir
```

- [ ] **Step 2: Diff against the design doc's Dockerfile flow**

Read `superpowers/specs/2026-08-04-agent2-mise-bootstrap-design.md`'s "Dockerfile flow" section and confirm each of its 6 numbered steps is present in the file above (OS prereqs → mise env/install → copy config → `mise bootstrap --yes` → dev user creation → `USER dev`/`WORKDIR`). Note the design doc's step 5 explicitly says the `userdel ubuntu` dance from `agent/Dockerfile` is **not** needed here since this base image is `debian:13-slim`, not `ubuntu:24.04` — the file above correctly omits it.

- [ ] **Step 3: Commit**

```bash
git add devcontainer/agent2/Dockerfile
git commit -m "Rewrite agent2/Dockerfile to install tooling via mise bootstrap"
```

---

### Task 3: Build and verify the image (user-run)

**Files:** none (verification only)

**Interfaces:**
- Consumes: the `agent2` service definition already in `devcontainer/docker-compose.yml`, and the Dockerfile/mise.toml from Tasks 1–2.

This environment has no docker access. Every step below must be run by the user on the host; report back the output for each before checking the box.

- [ ] **Step 1: Ask the user to build the image**

Ask the user to run, and paste back the output:

```bash
docker compose -f devcontainer/docker-compose.yml build agent2
```

Expected: build completes with no errors. If `mise bootstrap --yes` fails, the most likely culprit is the `aqua:gitlab-org/cli` package name (flagged as an open risk in the spec) — if that line errors, ask the user whether to search the aqua registry for the correct glab package name, or fall back to a manual `.deb` install kept outside mise for that one tool, and update `mise.toml` accordingly before retrying.

- [ ] **Step 2: Ask the user to start the container and open a shell**

Ask the user to run:

```bash
docker compose -f devcontainer/docker-compose.yml up -d agent2
docker compose -f devcontainer/docker-compose.yml exec agent2 whoami
```

Expected: `dev`.

- [ ] **Step 3: Ask the user to verify tools installed via `[tools]`**

Ask the user to run, and paste back the output:

```bash
docker compose -f devcontainer/docker-compose.yml exec agent2 bash -c '
  node --version
  python --version
  mcp-language-server --help
  typescript-language-server --version
  pyright --version
  glab --version
'
```

Expected: node prints a v26.x version, python prints 3.14.x, `mcp-language-server --help` prints usage (nonzero exit is fine, just confirm the binary runs), the other three print version strings without "command not found".

- [ ] **Step 4: Ask the user to verify tools installed via `[bootstrap.packages]`**

Ask the user to run, and paste back the output:

```bash
docker compose -f devcontainer/docker-compose.yml exec agent2 bash -c '
  jq --version
  rg --version
  shellcheck --version
  vim --version | head -1
  socat -V | head -1
  nc -h 2>&1 | head -1
  ssh -V
'
```

Expected: every command prints version/help output, none report "command not found".

- [ ] **Step 5: Ask the user to verify idempotency**

Ask the user to run a second build and confirm it completes without prompts or errors (mise's bootstrap is documented as idempotent):

```bash
docker compose -f devcontainer/docker-compose.yml build agent2
```

- [ ] **Step 6: Record verification result**

Once Steps 1–5 all pass, no commit is needed for this task (it's verification-only) — report completion to the user and stop, since replacing `agent` in `devcontainer.json` is explicitly out of scope for this round.

---
