# Mise Privilege and Trust Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the agent container's `dev` user from becoming root through `sudo mise`, make mise trust explicit and tied to file content, and make the README match what provisioning actually does.

**Architecture:** The privileged step (installing apt packages from the repo's `[bootstrap.packages]`) moves out of `provision.sh` (which runs as `dev` with `sudo`). The host scripts `ccc` / `ccc-rebuild` run it directly as root with `compose exec -u root`, and the sudoers entry is deleted. Root gets its own per-repo mise state volume that `dev` can't write to, which also removes the root-owned files that broke `dev`'s `mise install` in a shared state dir. `MISE_PARANOID=1` disables mise's automatic trust and ties trust to file content.

**Tech Stack:** Bash, Dockerfile (ubuntu:24.04), Docker Compose / podman-compose, mise 2026.10.x.

**Spec:** No separate spec. This plan comes from the investigation in the 2026-10-12 session. Its findings are copied into "Context" below, and the plan argues from them.

## Context (findings this plan addresses)

Numbering matches the investigation report:

1. **`sudo mise` is full root.** `/etc/sudoers.d/dev-mise` allows `dev ALL=(root) NOPASSWD:SETENV: /usr/local/bin/mise`. `sudo mise exec -- id -u` prints `0`, so `dev`, and Claude running as `dev`, can run any command as root. The Ubuntu base image also leaves `dev` (the renamed `ubuntu` user) in groups `adm, sudo, …`.
   - Root shares `dev`'s mise state: `sudo -E` keeps `HOME=/home/dev`, so root writes `trusted-configs/`, `tracked-configs/` and `incomplete-installs/` into `dev`'s `mise-state` volume as root. A root-owned `trusted-configs/` makes `dev`'s `mise install` fail with `failed to ln -sf /home/dev …/trusted-configs/home-dev-…: Permission denied`. This was reproduced.
2. **Automatic trust.** Since mise 2026.8.9, `mise install` / `exec` / `run` trust their active config automatically. This was reproduced: `dev`'s `mise install` in an untrusted repo silently trusted it. The README says "We don't auto-trust the mounted repo's config". Trust is also tied to the path, not the content, so a trusted `mise.toml` can be edited (for example by Claude) without asking again.
3. **Runtime bootstrap scope shrank.** Since `73f31b8`, runtime provisioning only runs `bootstrap packages apply` and `install`. A repo's other `[bootstrap]` parts (files, hooks, the `bootstrap` task, dotfiles, …) are silently ignored, but the README still says "`ccc`/`ccc-rebuild` run `mise bootstrap`".
4. **Wrong comment.** `provision.sh` says "-E preserves MISE_*/PATH", but sudoers `secure_path` replaces `PATH` even with `-E`.
7. **Redundant `mkdir`.** `Dockerfile` runs `mkdir -p … /home/dev/.local/state/mise` *after* `RUN mise install`, which already created that directory. Its stated purpose, seeding a dev-owned directory into new volumes, only holds by accident.

Verified behavior of `MISE_PARANOID=1` (mise 2026.10.8, tested in-container):
- Global-only `mise install` works and writes no trust link.
- In an untrusted repo with no TTY, `mise install` fails with "not trusted" and does not trust automatically.
- After `mise trust`, editing `mise.toml` makes `mise install` fail again, because trust is tied to content.
- Shims (`node --version`) in an untrusted repo still work and fall back to the global config.
- Host check (2026-10-12): a from-scratch `mise install` of all 13 global tools with `MISE_PARANOID=1` succeeded, and so did the root `bootstrap packages apply --dry-run`. Paranoid mode rejects none of the backends in use.
- The interactive trust prompt under paranoid mode was not observed directly; Task 4 step 1 confirms it.

## Decisions baked into this plan (confirm during review)

- **D1 - no `sudo` at all inside the agent container.** `dev` can no longer install apt packages ad hoc. The only way to get system packages is `[bootstrap.packages]` in `mise.toml`, applied by `ccc` / `ccc-rebuild`. Alternative rejected: a sudo wrapper script. It would still run root mise against `/workdir/mise.toml`, which Claude can edit, so it would still be root for the agent.
- **D2 - two trust prompts per repo (approved, with explanation).** Root and `dev` have separate trust stores. This is deliberate: `dev` must not be able to write root's trust. The first `ccc` in a repo with a `mise.toml`, and the first `ccc` after any edit to it, therefore prompts twice: once for system packages (root), once for tools (`dev`). Each prompt is preceded by an `echo` explaining it, printed only when a prompt will actually show. Detection uses `mise trust --show`, which prints `<file>: untrusted` for a new or edited config in paranoid mode. That was verified in-container; it prints `: trusted` once trusted, and `No trusted config files found.` when the repo has no config.
- **D3 - item 3 is fixed with documentation, not code (pending user confirmation that no repo relies on other `[bootstrap]` sections).** The supported runtime surface is `[bootstrap.packages]` and `[tools]` only. Running the full `mise bootstrap` as root would apply `dotfiles` / `user` / `repos` / `files` to root's home or run hooks as root, which is wrong for this container. The README is updated to say so.
- **D4 - root's state volume is per repo and has no fixed name**, like the existing `mise-state`, so trusting one repo doesn't trust another.

## Global Constraints

- Every shell script keeps `set -euo pipefail` and passes `shellcheck` (`shellcheck devcontainer/scripts/ccc devcontainer/scripts/ccc-rebuild devcontainer/agent/*.sh`).
- Docker and Podman compose files stay in sync: every change to `docker-compose.agent.yml` is mirrored in `docker-compose.agent.podman.yml`.
- `provision.sh` and the new root script must stay idempotent and fast (they run on every `ccc`).
- Never commit without explicit user instruction (user rule). Commit steps below are prepared commands that run only once the user says so.
- No test framework exists in this repo. Verification is static checks (`shellcheck`, `yamllint`, `docker compose config`) plus manual host checks. The agent container has no Docker access, so the user runs every `docker …` command on the host.

## Review Focus

- **Non-interactive `ccc -p "…"` in a repo whose `mise.toml` is untrusted or was just edited:** expect a clear mise "not trusted" error and a non-zero exit before Claude starts, not a hang. Verified in Task 4 step 4.
- **Repo with no `mise.toml` at all:** expect the root step and `mise install` to succeed with no prompt. Verified in Task 4 step 2.
- **Existing per-repo `mise-state` volumes from before this change** (with root-owned `trusted-configs/`): expect them to keep failing until the volume is removed, because nothing writes as root into them any more but old root-owned dirs remain. Covered by a migration note in the README (Task 3) and Task 4 step 1.
- **Podman rootless with `userns_mode: keep-id`:** `exec -u root` must still be able to run apt. Verified in Task 4 step 5, which is optional and needs a Podman host.
- **Claude editing `mise.toml` mid-session:** the next `ccc` must re-prompt for both trusts instead of silently applying the new content. Verified in Task 4 step 3.

---

### Task 1: Move privileged package install out of the container's sudo path (items 1, 4, 7)

**Files:**
- Create: `devcontainer/agent/provision-root.sh`
- Modify: `devcontainer/agent/Dockerfile` (sudo package, sudoers block, user groups, state dir `mkdir`, copy root script)
- Modify: `devcontainer/agent/provision.sh:1-5` (remove debug early exit), `:87-100` (drop the sudo step, rewrite comments)
- Modify: `devcontainer/docker-compose.agent.yml`, `devcontainer/docker-compose.agent.podman.yml` (add `mise-root-state` volume)
- Modify: `devcontainer/scripts/ccc:37`, `devcontainer/scripts/ccc-rebuild:29` (run the root step before `provision.sh`)

**Interfaces:**
- Produces: `/usr/local/sbin/provision-root.sh` in the image, owned by root with mode `0755` (`dev` can read it, not write it). It is invoked from the host as `$COMPOSE_CMD -p "$AGENT_COMPOSE_PROJECT_NAME" -f "$AGENT_COMPOSE_FILE" exec -u root agent /usr/local/sbin/provision-root.sh`.
- Produces: compose volume `mise-root-state` mounted at `/root/.local/state/mise`.

- [ ] **Step 1: Record the failing baseline.** On the host, in the current container, the user runs:

```sh
docker exec monorepo-2eba2711-agent-1 sudo mise exec -- id -u
```

Expected today: `0`, which shows finding 1.

- [ ] **Step 2: Create `devcontainer/agent/provision-root.sh`**

```bash
#!/bin/bash
set -euo pipefail

# Privileged provisioning for the agent container, run as root by the host
# scripts (`ccc`, `ccc-rebuild`) via `compose exec -u root`, never from
# inside the container: dev has no sudo access.
#
# Installs the system packages ([bootstrap.packages], e.g. apt:...) declared
# by the mounted repo's mise config, on top of the image's own
# /mise/config.toml.
#
# Root keeps its own mise state in /root/.local/state/mise (the
# mise-root-state volume), separate from dev's: dev can't forge root's trust
# decisions, and root never writes root-owned files into dev's state.
#
# Runs on every `ccc` and `ccc-rebuild`: keep it idempotent and fast.
cd /workdir

# Explain the upcoming mise trust prompt (only when there is one: new or
# edited repo config - paranoid mode ties trust to the file's contents)
if mise trust --show 2>/dev/null | grep -q ': untrusted$'; then
    echo "==> mise trust prompt 1/2 - SYSTEM PACKAGES (as root)"
    echo "    This repo's mise config is new or was modified since you last trusted it."
    echo "    Trusting it lets its [bootstrap.packages] be installed as root in the container."
    echo "    A second prompt follows for its [tools] (as dev): root and dev keep separate"
    echo "    trust decisions so the agent can't approve root installs on its own."
fi
mise bootstrap packages apply
```

- [ ] **Step 3: Update `devcontainer/agent/Dockerfile`.** Make these edits against the current file:

1. In the first `apt-get install` line, remove `sudo`:

```dockerfile
RUN apt-get update  \
    && apt-get -y --no-install-recommends install  \
        curl git ca-certificates build-essential \
    && rm -rf /var/lib/apt/lists/*
```

2. Replace the user-rename `RUN` so the renamed user drops the `ubuntu` user's supplementary groups (`adm`, `sudo`, …):

```dockerfile
RUN groupmod -n dev -g "$USER_GID" ubuntu \
    && usermod -l dev -u "$USER_UID" -d /home/dev -m -G "" ubuntu
```

3. Delete the whole sudoers block, meaning the two comment lines `# Allow dev to run mise with sudo` / `# Used in provision.sh …` and the `RUN echo "dev ALL=(root) …" … chmod 0440 …` instruction. In its place, add the root script:

```dockerfile
# Privileged provisioning, run by the host scripts as root via
# `compose exec -u root` - dev has no sudo. Root-owned so dev can't edit it.
COPY provision-root.sh /usr/local/sbin/provision-root.sh
RUN chmod 755 /usr/local/sbin/provision-root.sh
```

4. Item 7: move the state-dir `mkdir` to right after `USER dev`, *before* `RUN mise install`, and stop relying on mise to create the directory:

```dockerfile
USER dev

# Pre-create dirs owned by dev so named volumes mounted here are seeded with
# dev's ownership instead of being root-owned and unwritable. Done before
# any mise call so the ownership never depends on mise's own side effects.
RUN mkdir -p /home/dev/.config/glab-cli /home/dev/.claude /home/dev/.local/state/mise

RUN mise install
```

Then delete the old `mkdir -p` line and its comment further down, the ones after `WORKDIR /workdir`.

- [ ] **Step 4: Update `devcontainer/agent/provision.sh`**

1. Delete lines 4-5:

```bash
echo "Early exit to debug mise"
exit
```

2. Replace the mise block (the comment starting `# Run mise to install tooling …` through `mise install`) with:

```bash
# Install the mounted repo's [tools] (on top of the image's own
# /mise/config.toml) as dev, so any cache/build dirs they create are
# dev-owned.
#
# System packages ([bootstrap.packages]) need root and are installed before
# this script by provision-root.sh, which the host scripts run as root.
#
# mise runs in paranoid mode (MISE_PARANOID in the Dockerfile): the repo's
# config must be explicitly trusted, interactively, and editing it revokes
# the trust. Trust decisions persist in the mise-state volume.
if (cd /workdir && mise trust --show 2>/dev/null | grep -q ': untrusted$'); then
    echo "==> mise trust prompt 2/2 - TOOLS (as dev)"
    echo "    Trusting this repo's mise config lets its [tools] be installed as dev."
    echo "    You already answered the root prompt; dev keeps its own trust decisions."
fi
mise install
```

- [ ] **Step 5: Add the `mise-root-state` volume to both compose files.** In `devcontainer/docker-compose.agent.yml` **and** `devcontainer/docker-compose.agent.podman.yml`:

Under `services.agent.volumes`, right after the `mise-state` line:

```yaml
      - mise-root-state:/root/.local/state/mise
```

Under top-level `volumes:`, right after the `mise-state:` entry:

```yaml
  # Root's own mise state (trust decisions for [bootstrap.packages]), kept
  # apart from dev's so dev can't write root's trust. Per-repo, like
  # mise-state.
  mise-root-state:
```

- [ ] **Step 6: Run the root step from the host scripts.** In both `devcontainer/scripts/ccc` and `devcontainer/scripts/ccc-rebuild`, insert this immediately *before* the existing `… exec agent /home/dev/provision.sh` line:

```bash
# System packages need root: run as root from here since dev has no sudo
$COMPOSE_CMD -p "$AGENT_COMPOSE_PROJECT_NAME" -f "$AGENT_COMPOSE_FILE" exec -u root agent /usr/local/sbin/provision-root.sh
```

- [ ] **Step 7: Static checks**

Run (inside the agent container):

```sh
shellcheck devcontainer/scripts/ccc devcontainer/scripts/ccc-rebuild devcontainer/agent/provision.sh devcontainer/agent/provision-root.sh
yamllint -d relaxed devcontainer/docker-compose.agent.yml devcontainer/docker-compose.agent.podman.yml
grep -rn 'sudo' devcontainer/ README.md
```

Expected: shellcheck prints nothing. yamllint reports no errors. `grep` finds no `sudo` in `devcontainer/`; README hits are fixed in Task 3.

The user then runs this on the host from any repo:

```sh
WORKSPACE_FOLDER=$PWD DEV_UID=$(id -u) DEV_GID=$(id -g) docker compose -f "$CLAUDE_DEVCONTAINER_HOME/devcontainer/docker-compose.agent.yml" config | grep -A1 mise-root-state
```

Expected: the volume is listed and mounted at `/root/.local/state/mise`.

- [ ] **Step 8: Commit (only on user instruction)**

```bash
git add devcontainer/agent/provision-root.sh devcontainer/agent/Dockerfile devcontainer/agent/provision.sh \
  devcontainer/docker-compose.agent.yml devcontainer/docker-compose.agent.podman.yml \
  devcontainer/scripts/ccc devcontainer/scripts/ccc-rebuild
git commit -m "Agent - Drop in-container sudo, run system package install as root from host"
```

---

### Task 2: Make mise trust explicit and tied to content (item 2)

**Files:**
- Modify: `devcontainer/agent/Dockerfile` (the `ENV MISE_*` block)

**Interfaces:**
- Consumes: Task 1's split (root step via `provision-root.sh`, dev step `mise install` in `provision.sh`). Both inherit image `ENV`, including under `exec -u root`.
- Produces: `MISE_PARANOID=1` in every mise process in the container.

- [ ] **Step 1: Record the failing baseline (in-container, no Docker needed)**

```sh
SP=$(mktemp -d); mkdir $SP/repo $SP/state; printf '[tools]\n' > $SP/repo/mise.toml
(cd $SP/repo && MISE_STATE_DIR=$SP/state mise install </dev/null >/dev/null 2>&1); ls $SP/state/trusted-configs
```

Expected today: an entry `…repo-<hash>` exists, which shows the repo was trusted automatically.

- [ ] **Step 2: Add paranoid mode to the Dockerfile `ENV` block**, after `ENV MISE_INSTALL_PATH=…`:

```dockerfile
# Paranoid mode: no automatic trust (mise >= 2026.8.9 otherwise trusts a
# repo's config on `mise install/exec/run`), and trust is tied to the file's
# contents, so editing a trusted mise.toml (e.g. by the agent) requires
# trusting it again. See https://mise.jdx.dev/paranoid.html
ENV MISE_PARANOID="1"
```

- [ ] **Step 3: Verify the behavior in-container (no rebuild needed: the env var can be passed directly)**

```sh
SP=$(mktemp -d); mkdir $SP/repo $SP/state; printf '[tools]\n' > $SP/repo/mise.toml
cd $SP/repo
MISE_PARANOID=1 MISE_STATE_DIR=$SP/state mise install </dev/null; echo "rc=$?"     # expect non-zero, "not trusted"
ls $SP/state/trusted-configs 2>&1                                                 # expect: No such file or directory
MISE_PARANOID=1 MISE_STATE_DIR=$SP/state mise trust && MISE_PARANOID=1 MISE_STATE_DIR=$SP/state mise install; echo "rc=$?"  # expect 0
echo '# edit' >> mise.toml
MISE_PARANOID=1 MISE_STATE_DIR=$SP/state mise install </dev/null; echo "rc=$?"   # expect non-zero again
cd /home/dev && MISE_PARANOID=1 MISE_STATE_DIR=$SP/state mise install; echo "rc=$?"  # global config only: expect 0
```

- [ ] **Step 4: Verify a full image build still works in paranoid mode.** The build-time `mise install` downloads every tool, so the user runs this on the host:

```sh
cd "$CLAUDE_DEVCONTAINER_HOME/devcontainer" && DEV_UID=$(id -u) DEV_GID=$(id -g) WORKSPACE_FOLDER=$PWD \
  docker compose -f docker-compose.agent.yml build --no-cache agent
```

Expected: the build succeeds. If any backend (`go:`, `npm:`, `pipx:`, `gitlab:`) is rejected in paranoid mode, stop and report it. Don't drop paranoid mode quietly.

- [ ] **Step 5: Commit (only on user instruction)**

```bash
git add devcontainer/agent/Dockerfile
git commit -m "Agent - Run mise in paranoid mode to require explicit, content-bound trust"
```

---

### Task 3: Make the README match the new behavior (items 1, 2, 3)

**Files:**
- Modify: `README.md`, section `## System tools` (currently lines 263-283)

**Interfaces:**
- Consumes: behavior from Tasks 1-2 (root script, two trust stores, paranoid mode, scope limited to `[bootstrap.packages]` + `[tools]`).

- [ ] **Step 1: Replace the body of `## System tools` (from line 265 through the end of its `Note:` list, just before `## Desktop notifications`) with:**

````markdown
We use [`mise.toml`](./devcontainer/agent/mise.toml) to define all the packages, language runtimes and
other tools (`shellcheck`, `jq`, ...) which must be installed in the agent container.

The system automatically picks up repo-specific dependencies: if the mounted repo has its own
`mise.toml`/`.mise.toml`, on every `ccc`/`ccc-rebuild`:

1. Its `[bootstrap.packages]` (e.g. `"apt:default-mysql-client" = "latest"`) are installed by
   [`provision-root.sh`](./devcontainer/agent/provision-root.sh), run **as root from the host**
   with `compose exec -u root`.
2. Its `[tools]` are installed by [`provision.sh`](./devcontainer/agent/provision.sh) as the
   unprivileged `dev` user.

Only these two sections are supported. Other `[bootstrap]` parts of a repo's config (files,
dotfiles, repos, hooks, the `bootstrap` task, ...) are **not** applied.

The `dev` user has no `sudo` access in the container: installing a system package means adding
it to the repo's `[bootstrap.packages]` and running `ccc` again.

### Trusting a repo's mise config

`mise` runs in [paranoid mode](https://mise.jdx.dev/paranoid.html) in the container:

- A repo's config is never trusted automatically - `ccc`/`ccc-rebuild` show mise's interactive
  prompt instead.
- Trust is bound to the file's contents: after any edit to the repo's mise config (by you or by
  Claude) you are prompted again on the next `ccc`.
- Root (system packages) and `dev` (tools) keep separate trust decisions, so the first `ccc` in
  a repo - and the first one after an edit - prompts **twice**. This is deliberate: `dev` (and so
  Claude) cannot write root's trust decisions.

Trust decisions are stored per repo in two nameless docker volumes, `mise-state` (dev) and
`mise-root-state` (root), so each repo keeps its decisions separately and nothing is trusted
across repos.

Notes:
- When running `ccc` non-interactively (e.g. `ccc -p "..."`) mise can't prompt and fails. Run an
  interactive `ccc` once first to accept the prompts.
- Upgrading from a version of this setup that used `sudo mise`: the repo's old `mise-state`
  volume may contain root-owned directories that make `mise install` fail with
  `Permission denied`. Remove it once per repo, from the host:
  `docker compose -p <project> -f "$CLAUDE_DEVCONTAINER_HOME/devcontainer/docker-compose.agent.yml" down`
  then `docker volume rm <project>_mise-state` (`<project>` is the agent container's compose
  project name, e.g. `monorepo-2eba2711`).
````

- [ ] **Step 2: Check no stale claims remain**

```sh
grep -nE 'sudo|mise bootstrap|auto-trust' README.md
```

Expected: only the lines written in Step 1 match. In particular, nothing says "run `mise bootstrap`" or "We don't auto-trust".

- [ ] **Step 3: Commit (only on user instruction)**

```bash
git add README.md
git commit -m "README - Document mise privilege split, paranoid trust and supported scope"
```

---

### Task 4: End-to-end verification on the host

No file changes. The user runs everything here on the host, because the agent container has no Docker access. Run it after Tasks 1-3, from a checkout that contains them.

- [ ] **Step 1: Fresh start for the test repo (monorepo)**

```sh
cd ~/dev/monorepo
docker compose -p monorepo-2eba2711 -f "$CLAUDE_DEVCONTAINER_HOME/devcontainer/docker-compose.agent.yml" down
docker volume rm monorepo-2eba2711_mise-state
ccc-rebuild
```

Expected:
- Two trust prompts: one from the root step, one from `provision.sh`.
- `default-mysql-client` gets installed.
- `mise install` completes, and you get a shell.

Then:

```sh
docker exec monorepo-2eba2711-agent-1 ls -la /home/dev/.local/state/mise /home/dev/.local/state/mise/trusted-configs
docker exec monorepo-2eba2711-agent-1 sh -c 'command -v sudo; id'
docker exec monorepo-2eba2711-agent-1 mysql --version
```

Expected:
- Nothing in dev's state dir is owned by root.
- `command -v sudo` prints nothing.
- `id` shows only group `dev`.
- `mysql` prints a version.

Run `ccc` again: no prompts.

- [ ] **Step 2: Repo without a mise config**

```sh
cd "$CLAUDE_DEVCONTAINER_HOME" && ccc
```

Expected: no trust prompt, both steps succeed, and you get a shell.

- [ ] **Step 3: Content-bound trust**

```sh
cd ~/dev/monorepo && echo '# touch' >> mise.toml && ccc     # expect both prompts again
git checkout -- mise.toml
```

- [ ] **Step 4: Non-interactive run with untrusted config**

```sh
cd ~/dev/monorepo && echo '# touch' >> mise.toml && ccc -p "say hi" </dev/null; echo "rc=$?"
git checkout -- mise.toml
```

Expected: mise "not trusted" error, a non-zero `rc`, and no hang.

- [ ] **Step 5 (optional, Podman host): repeat Step 1 with `CLAUDE_DEVCONTAINER_ENGINE=podman`.** Expected: the same results, in particular that `exec -u root` can run `apt-get`.

---

## Out of scope (from the same investigation, not requested)

- Item 5: apt lists (52M) left in the image and runtime installs that don't use `--update`.
- Item 6 is mostly resolved as a side effect of Task 1: root no longer writes into dev's state. It isn't verified separately.
- Pinning `MISE_VERSION` in the Dockerfile.
- Restoring the dropped revert `aac123e`. This plan assumes the current `HEAD` (Ubuntu base). On Debian, Task 1 step 3.2 does not apply (no `ubuntu` user) and the existing `useradd` line is kept.
