# Docker/Podman Compatibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let `ccc`, `ccc-code`, `ccc-compose`, and `ccc-rebuild` work with either Docker or Podman as the container backend.

**Architecture:** A new sourced helper, `devcontainer/scripts/lib/engine.sh`, detects the engine (env var override, else Docker-if-reachable, else Podman) and exports `ENGINE_BIN`/`COMPOSE_CMD`/`COMPOSE_FILE`. All four `ccc*` scripts source it and swap their hardcoded `docker`/`docker compose`/`docker-compose.yml` references for these variables. A new standalone `docker-compose.podman.yml` replaces `docker-compose.yml` under Podman and omits the `claude-desktop-notification` service entirely.

**Tech Stack:** Bash (`set -euo pipefail` throughout, matching every existing script in this repo), Docker Compose v2 / Podman's built-in `compose` subcommand (4.7+), `@devcontainers/cli` via `npx`.

## Global Constraints

- No automated test framework exists in this repo (confirmed: no `package.json`-equivalent, no `test/` dir, no CI). Verification in this plan is: `shellcheck`, `bash -n` syntax checks, and manual logic-trace tests using faked `docker`/`podman` binaries on `PATH` — this matches the design spec's own "Testing" section, which specifies manual verification as the project convention.
- Podman support requires Podman 4.7+ (built-in `podman compose`); no fallback to standalone `podman-compose` is implemented.
- `CLAUDE_DEVCONTAINER_ENGINE`, if set to a binary that isn't installed, must fail loudly — never silently fall back to auto-detection.
- Every script keeps `set -euo pipefail` and the existing `CLAUDE_DEVCONTAINER_HOME` unset-check pattern already at the top of `ccc`, `ccc-code`, `ccc-compose`, `ccc-rebuild`.
- `docker-compose.podman.yml` is a full standalone file (not a Compose override merged via multiple `-f` flags) and contains only `mcp-everything` + the `mcp-net` network — `claude-desktop-notification` is not started under Podman.

---

### Task 1: `lib/engine.sh` — engine detection

**Files:**
- Create: `devcontainer/scripts/lib/engine.sh`

**Interfaces:**
- Consumes: env var `CLAUDE_DEVCONTAINER_ENGINE` (optional), env var `DEVCONTAINER_DIR` (must be set by the caller before sourcing — absolute path to the `devcontainer/` directory).
- Produces (exported for callers): `ENGINE_BIN` (string, `"docker"` or `"podman"`), `COMPOSE_CMD` (string, `"$ENGINE_BIN compose"`, meant to be word-split unquoted by callers), `COMPOSE_FILE` (string, absolute path to `$DEVCONTAINER_DIR/docker-compose.yml` or `$DEVCONTAINER_DIR/docker-compose.podman.yml`).

- [ ] **Step 1: Write the verification harness**

Create a scratch test script (not committed — this repo has no test directory convention) at `/tmp/claude-1000/-workdir/c7d0a802-ea5f-40af-92e2-3228201e53f2/scratchpad/test-engine.sh`:

```bash
#!/bin/bash
set -euo pipefail

FAKES="$(mktemp -d)"
trap 'rm -rf "$FAKES"' EXIT

mkdir -p "$FAKES/docker-ok" "$FAKES/docker-unreachable" "$FAKES/podman-only"

# docker-ok: docker installed, daemon reachable
cat > "$FAKES/docker-ok/docker" <<'EOF'
#!/bin/bash
[ "$1" = "info" ] && exit 0
echo "fake docker $*"
EOF
chmod +x "$FAKES/docker-ok/docker"

# docker-unreachable: docker installed, daemon NOT reachable; podman present in podman-only dir, combine both dirs on PATH for this case
cat > "$FAKES/docker-unreachable/docker" <<'EOF'
#!/bin/bash
[ "$1" = "info" ] && exit 1
echo "fake docker $*"
EOF
chmod +x "$FAKES/docker-unreachable/docker"

cat > "$FAKES/podman-only/podman" <<'EOF'
#!/bin/bash
echo "fake podman $*"
EOF
chmod +x "$FAKES/podman-only/podman"

DEVCONTAINER_DIR="/fake/devcontainer"
ENGINE_SH="/workdir/devcontainer/scripts/lib/engine.sh"

run_case () {
    local name="$1" path="$2" envvar="${3:-}"
    ( 
      export PATH="$path"
      export DEVCONTAINER_DIR
      [ -n "$envvar" ] && export CLAUDE_DEVCONTAINER_ENGINE="$envvar"
      # shellcheck disable=SC1090
      source "$ENGINE_SH"
      echo "$name: ENGINE_BIN=$ENGINE_BIN COMPOSE_CMD=$COMPOSE_CMD COMPOSE_FILE=$COMPOSE_FILE"
    )
}

echo "--- case: docker reachable, no override -> expect docker ---"
run_case docker-reachable "$FAKES/docker-ok"

echo "--- case: only podman on PATH -> expect podman ---"
run_case podman-only "$FAKES/podman-only"

echo "--- case: docker unreachable, podman present -> expect podman ---"
run_case docker-unreachable-podman-present "$FAKES/docker-unreachable:$FAKES/podman-only"

echo "--- case: override forces podman even though docker reachable -> expect podman ---"
run_case override-podman "$FAKES/docker-ok:$FAKES/podman-only" podman

echo "--- case: override to a binary not installed -> expect error, exit 1 ---"
if run_case override-missing "$FAKES/docker-ok" nonexistent-engine 2>/tmp/err.txt; then
    echo "FAIL: expected non-zero exit"
    exit 1
else
    echo "override-missing: correctly failed: $(cat /tmp/err.txt)"
fi

echo "--- case: neither engine present -> expect error, exit 1 ---"
EMPTY="$(mktemp -d)"
if run_case neither-present "$EMPTY" 2>/tmp/err2.txt; then
    echo "FAIL: expected non-zero exit"
    exit 1
else
    echo "neither-present: correctly failed: $(cat /tmp/err2.txt)"
fi
rmdir "$EMPTY"

echo "ALL CASES RAN"
```

Make it executable: `chmod +x /tmp/claude-1000/-workdir/c7d0a802-ea5f-40af-92e2-3228201e53f2/scratchpad/test-engine.sh`

- [ ] **Step 2: Run it to verify it fails (engine.sh doesn't exist yet)**

Run: `bash /tmp/claude-1000/-workdir/c7d0a802-ea5f-40af-92e2-3228201e53f2/scratchpad/test-engine.sh`
Expected: fails on the first `run_case` with a "No such file or directory" error sourcing `/workdir/devcontainer/scripts/lib/engine.sh`.

- [ ] **Step 3: Write `devcontainer/scripts/lib/engine.sh`**

```bash
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
else
    COMPOSE_FILE="$DEVCONTAINER_DIR/docker-compose.yml"
fi

export ENGINE_BIN COMPOSE_CMD COMPOSE_FILE
```

- [ ] **Step 4: Run the harness again to verify all cases pass**

Run: `bash /tmp/claude-1000/-workdir/c7d0a802-ea5f-40af-92e2-3228201e53f2/scratchpad/test-engine.sh`
Expected output ends with `ALL CASES RAN`, and each case line shows the expected `ENGINE_BIN`:
```
--- case: docker reachable, no override -> expect docker ---
docker-reachable: ENGINE_BIN=docker COMPOSE_CMD=docker compose COMPOSE_FILE=/fake/devcontainer/docker-compose.yml
--- case: only podman on PATH -> expect podman ---
podman-only: ENGINE_BIN=podman COMPOSE_CMD=podman compose COMPOSE_FILE=/fake/devcontainer/docker-compose.podman.yml
--- case: docker unreachable, podman present -> expect podman ---
docker-unreachable-podman-present: ENGINE_BIN=podman COMPOSE_CMD=podman compose COMPOSE_FILE=/fake/devcontainer/docker-compose.podman.yml
--- case: override forces podman even though docker reachable -> expect podman ---
override-podman: ENGINE_BIN=podman COMPOSE_CMD=podman compose COMPOSE_FILE=/fake/devcontainer/docker-compose.podman.yml
--- case: override to a binary not installed -> expect error, exit 1 ---
override-missing: correctly failed: engine.sh: CLAUDE_DEVCONTAINER_ENGINE=nonexistent-engine but 'nonexistent-engine' is not installed.
--- case: neither engine present -> expect error, exit 1 ---
neither-present: correctly failed: engine.sh: no container engine found. Install Docker or Podman (4.7+), or set CLAUDE_DEVCONTAINER_ENGINE. See README.md.
ALL CASES RAN
```

If any case doesn't match, fix `engine.sh` and re-run before moving on.

- [ ] **Step 5: Run shellcheck**

Run: `shellcheck devcontainer/scripts/lib/engine.sh`
Expected: no output (no warnings/errors). Fix any reported issues.

- [ ] **Step 6: Commit**

```bash
git add devcontainer/scripts/lib/engine.sh
git commit -m "Add engine.sh: docker/podman backend detection and override"
```

---

### Task 2: `docker-compose.podman.yml`

**Files:**
- Create: `devcontainer/docker-compose.podman.yml`
- Reference (unchanged): `devcontainer/docker-compose.yml`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: a compose file consumed by Task 3-6's scripts via `$COMPOSE_FILE` when `ENGINE_BIN=podman`.

- [ ] **Step 1: Create the file**

```yaml
services:
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
```

Note: `claude-desktop-notification` is intentionally omitted — it is not started under Podman (see design spec, "Notification service — scope").

- [ ] **Step 2: Validate YAML syntax**

Run: `python3 -c "import yaml, sys; yaml.safe_load(open('devcontainer/docker-compose.podman.yml'))" && echo VALID`
Expected: `VALID`

- [ ] **Step 3: Commit**

```bash
git add devcontainer/docker-compose.podman.yml
git commit -m "Add docker-compose.podman.yml (no notification service)"
```

---

### Task 3: `ccc` — use `lib/engine.sh`

**Files:**
- Modify: `devcontainer/scripts/ccc`

**Interfaces:**
- Consumes: `ENGINE_BIN`, `COMPOSE_CMD`, `COMPOSE_FILE` from Task 1's `devcontainer/scripts/lib/engine.sh`; `docker-compose.podman.yml` from Task 2.
- Produces: nothing consumed by later tasks (each `ccc*` script is independent).

- [ ] **Step 1: Edit `devcontainer/scripts/ccc`**

Current relevant lines:
```bash
DEVCONTAINER_DIR="$CLAUDE_DEVCONTAINER_HOME/devcontainer"
DEVCONTAINER_JSON="$DEVCONTAINER_DIR/devcontainer.json"

WORKSPACE_FOLDER="$(pwd)"
```
```bash
# Start the global singleton services (claude-desktop-notification, mcp-everything, ...) — idempotent if already running.
docker compose -f "$DEVCONTAINER_DIR/docker-compose.yml" up -d --wait

# Create/start the workspace-scoped agent container, then exec a shell in it.
npx @devcontainers/cli up --workspace-folder "$WORKSPACE_FOLDER" --config "$DEVCONTAINER_JSON"
exec npx @devcontainers/cli exec --workspace-folder "$WORKSPACE_FOLDER" --config "$DEVCONTAINER_JSON" bash
```

Replace with:
```bash
DEVCONTAINER_DIR="$CLAUDE_DEVCONTAINER_HOME/devcontainer"
DEVCONTAINER_JSON="$DEVCONTAINER_DIR/devcontainer.json"

WORKSPACE_FOLDER="$(pwd)"

# shellcheck source=lib/engine.sh
source "$DEVCONTAINER_DIR/scripts/lib/engine.sh"
```
```bash
# Start the global singleton services (mcp-everything, and claude-desktop-notification under Docker) — idempotent if already running.
$COMPOSE_CMD -f "$COMPOSE_FILE" up -d --wait

# Create/start the workspace-scoped agent container, then exec a shell in it.
npx @devcontainers/cli up --workspace-folder "$WORKSPACE_FOLDER" --config "$DEVCONTAINER_JSON" --docker-path "$ENGINE_BIN"
exec npx @devcontainers/cli exec --workspace-folder "$WORKSPACE_FOLDER" --config "$DEVCONTAINER_JSON" --docker-path "$ENGINE_BIN" bash
```

(The `source` line goes immediately after `WORKSPACE_FOLDER="$(pwd)"`, before the `export DEV_UID` block — order relative to `DEV_UID`/bootstrap lines doesn't matter, but it must come after `DEVCONTAINER_DIR` is set.)

- [ ] **Step 2: Syntax check**

Run: `bash -n devcontainer/scripts/ccc`
Expected: no output (exit 0).

- [ ] **Step 3: Shellcheck**

Run: `shellcheck devcontainer/scripts/ccc`
Expected: no output. Fix any reported issues (the `source` line will need the `# shellcheck source=lib/engine.sh` directive shown above to avoid a follow-file warning).

- [ ] **Step 4: Commit**

```bash
git add devcontainer/scripts/ccc
git commit -m "ccc: use engine.sh for docker/podman backend selection"
```

---

### Task 4: `ccc-rebuild` — use `lib/engine.sh`

**Files:**
- Modify: `devcontainer/scripts/ccc-rebuild`

**Interfaces:**
- Consumes: same as Task 3.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Edit `devcontainer/scripts/ccc-rebuild`**

Current relevant lines:
```bash
DEVCONTAINER_DIR="$CLAUDE_DEVCONTAINER_HOME/devcontainer"
DEVCONTAINER_JSON="$DEVCONTAINER_DIR/devcontainer.json"

WORKSPACE_FOLDER="$(pwd)"
```
```bash
# Start the global singleton services (claude-desktop-notification, mcp-everything, ...) — idempotent if already running.
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

Replace with:
```bash
DEVCONTAINER_DIR="$CLAUDE_DEVCONTAINER_HOME/devcontainer"
DEVCONTAINER_JSON="$DEVCONTAINER_DIR/devcontainer.json"

WORKSPACE_FOLDER="$(pwd)"

# shellcheck source=lib/engine.sh
source "$DEVCONTAINER_DIR/scripts/lib/engine.sh"
```
```bash
# Start the global singleton services (mcp-everything, and claude-desktop-notification under Docker) — idempotent if already running.
echo "Start up singleton services"
$COMPOSE_CMD -f "$COMPOSE_FILE" up -d --wait

# Force a fresh container and image build, then exec a shell in it.
echo "Rebuild devcontainer"
npx @devcontainers/cli up \
    --workspace-folder "$WORKSPACE_FOLDER" \
    --config "$DEVCONTAINER_JSON" \
    --docker-path "$ENGINE_BIN" \
    --remove-existing-container

echo "Start devcontainer"
exec npx @devcontainers/cli exec --workspace-folder "$WORKSPACE_FOLDER" --config "$DEVCONTAINER_JSON" --docker-path "$ENGINE_BIN" bash
```

- [ ] **Step 2: Syntax check**

Run: `bash -n devcontainer/scripts/ccc-rebuild`
Expected: no output.

- [ ] **Step 3: Shellcheck**

Run: `shellcheck devcontainer/scripts/ccc-rebuild`
Expected: no output. Fix any reported issues.

- [ ] **Step 4: Commit**

```bash
git add devcontainer/scripts/ccc-rebuild
git commit -m "ccc-rebuild: use engine.sh for docker/podman backend selection"
```

---

### Task 5: `ccc-code` — use `lib/engine.sh`

**Files:**
- Modify: `devcontainer/scripts/ccc-code`

**Interfaces:**
- Consumes: same as Task 3.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Edit `devcontainer/scripts/ccc-code`**

Current relevant lines:
```bash
DEVCONTAINER_DIR="$CLAUDE_DEVCONTAINER_HOME/devcontainer"
DEVCONTAINER_JSON="$DEVCONTAINER_DIR/devcontainer.json"

WORKSPACE_FOLDER="$(pwd)"
```
```bash
# Start the global singleton services (claude-desktop-notification, mcp-everything, ...) — idempotent if already running.
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
```

Replace with:
```bash
DEVCONTAINER_DIR="$CLAUDE_DEVCONTAINER_HOME/devcontainer"
DEVCONTAINER_JSON="$DEVCONTAINER_DIR/devcontainer.json"

WORKSPACE_FOLDER="$(pwd)"

# shellcheck source=lib/engine.sh
source "$DEVCONTAINER_DIR/scripts/lib/engine.sh"
```
```bash
# Start the global singleton services (mcp-everything, and claude-desktop-notification under Docker) — idempotent if already running.
$COMPOSE_CMD -f "$COMPOSE_FILE" up -d --wait

# Create/start the workspace-scoped agent container (idempotent: reuses the
# existing container for this workspace folder if one is already running,
# so running this script twice from the same directory attaches two VS Code
# windows to the same container rather than creating a second one).
npx @devcontainers/cli up --workspace-folder "$WORKSPACE_FOLDER" --config "$DEVCONTAINER_JSON" --docker-path "$ENGINE_BIN"

# Find the container the CLI just created/reused, via the same
# `devcontainer.local_folder` label the CLI itself uses for this lookup.
CONTAINER_ID="$("$ENGINE_BIN" ps -q --filter "label=devcontainer.local_folder=${WORKSPACE_FOLDER}")"
if [ -z "$CONTAINER_ID" ]; then
    echo "ccc-code: could not find a running agent container for $WORKSPACE_FOLDER" >&2
    exit 1
fi
CONTAINER_NAME="$("$ENGINE_BIN" inspect -f '{{.Name}}' "$CONTAINER_ID")" # includes leading "/"
```

- [ ] **Step 2: Syntax check**

Run: `bash -n devcontainer/scripts/ccc-code`
Expected: no output.

- [ ] **Step 3: Shellcheck**

Run: `shellcheck devcontainer/scripts/ccc-code`
Expected: no output. Fix any reported issues.

- [ ] **Step 4: Commit**

```bash
git add devcontainer/scripts/ccc-code
git commit -m "ccc-code: use engine.sh for docker/podman backend selection"
```

---

### Task 6: `ccc-compose` — use `lib/engine.sh`

**Files:**
- Modify: `devcontainer/scripts/ccc-compose`

**Interfaces:**
- Consumes: same as Task 3.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Edit `devcontainer/scripts/ccc-compose`**

Current full body (after the `CLAUDE_DEVCONTAINER_HOME` check):
```bash
# Passed through so the compose file's UID interpolation resolves correctly.
export DEV_UID
DEV_UID="$(id -u)"

exec docker compose -f "$CLAUDE_DEVCONTAINER_HOME/devcontainer/docker-compose.yml" "$@"
```

Replace with:
```bash
DEVCONTAINER_DIR="$CLAUDE_DEVCONTAINER_HOME/devcontainer"

# shellcheck source=lib/engine.sh
source "$DEVCONTAINER_DIR/scripts/lib/engine.sh"

# Passed through so the compose file's UID interpolation resolves correctly.
export DEV_UID
DEV_UID="$(id -u)"

exec $COMPOSE_CMD -f "$COMPOSE_FILE" "$@"
```

- [ ] **Step 2: Syntax check**

Run: `bash -n devcontainer/scripts/ccc-compose`
Expected: no output.

- [ ] **Step 3: Shellcheck**

Run: `shellcheck devcontainer/scripts/ccc-compose`
Expected: no output (note: `exec $COMPOSE_CMD ...` unquoted is intentional word-splitting — shellcheck will flag SC2086 here; add `# shellcheck disable=SC2086` on the line above it since `COMPOSE_CMD` is a controlled two-word string, not user input).

- [ ] **Step 4: Commit**

```bash
git add devcontainer/scripts/ccc-compose
git commit -m "ccc-compose: use engine.sh for docker/podman backend selection"
```

---

### Task 7: README updates

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: nothing (documentation only).
- Produces: nothing.

- [ ] **Step 1: Update "System requirements" (README.md lines 11-15)**

Current:
```markdown
System requirements:

- `docker` (TODO podman)
- `node` + `npx` (TODO use other sources for devcontainer/cli
- If using VSCode: The devcontainer extension
```

Replace with:
```markdown
System requirements:

- `docker`, or `podman` 4.7+ (for its built-in `podman compose` subcommand)
- `node` + `npx` (TODO use other sources for devcontainer/cli
- If using VSCode: The devcontainer extension

By default the engine is auto-detected: Docker is used if installed and its
daemon is reachable, otherwise Podman is used if installed. Set
`CLAUDE_DEVCONTAINER_ENGINE=docker` or `CLAUDE_DEVCONTAINER_ENGINE=podman` to
force a specific engine (e.g. on a machine with both installed) — if set to
an engine that isn't installed, the `ccc*` commands fail with an error
rather than silently falling back.
```

- [ ] **Step 2: Update the "Requires" line under Setup (README.md line 66-67)**

Current:
```markdown
Requires: Docker with Compose v2, `npx` (Node.js), and — for notifications —
a Linux host with PulseAudio and D-Bus running in the user session.
```

Replace with:
```markdown
Requires: Docker with Compose v2 (or Podman 4.7+), `npx` (Node.js), and — for
notifications, Docker only, see "Known limitations" below — a Linux host
with PulseAudio and D-Bus running in the user session.
```

- [ ] **Step 3: Add a "Known limitations" section**

Find the `## Setup` section's end (right before `## Architecture` at README.md line 69) and insert a new section between them:

```markdown
## Known limitations

- **Desktop notifications are Docker-only.** Under Podman, the
  `claude-desktop-notification` singleton service is not started at all —
  `devcontainer/docker-compose.podman.yml` omits it. Its AppArmor/PulseAudio/
  D-Bus/host-networking setup is Docker-specific and hasn't been
  reimplemented for Podman's confinement and rootless-networking model.
  `mcp-everything` and the agent container work the same under both engines.
```

- [ ] **Step 4: Proofread the diff**

Run: `git diff README.md`
Expected: the three changes above, nothing else. Read through it once for wording/typos.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "README: document docker/podman backend selection"
```

---

## After implementation: manual end-to-end verification

This repo has no CI and no Docker/Podman available in a typical agent sandbox, so the following must be run by a human on a real machine — call this out explicitly when handing off, don't claim it as done:

1. On a Docker host: run `ccc` in a test repo, confirm unchanged behavior (agent container comes up, shell drops in, notifications still fire).
2. On a Podman-only host/VM (Podman 4.7+): run `ccc`, confirm the agent container comes up and drops into a shell, `mcp-everything` is reachable from inside it, and `podman ps` shows no `claude-desktop-notification` container.
3. On a machine with both installed: confirm `CLAUDE_DEVCONTAINER_ENGINE=docker ccc` and `CLAUDE_DEVCONTAINER_ENGINE=podman ccc` each force the expected engine.
4. Confirm `ccc-compose ps` and `ccc-code` work under both engines.
