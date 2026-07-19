# Docker/Podman compatibility — design

## Goal

Make the devcontainer tooling (`ccc`, `ccc-code`, `ccc-compose`, `ccc-rebuild`) work with
either Docker or Podman as the container backend, switching between them with as little
friction as possible. Today `docker` is hardcoded in all four scripts and in
`docker-compose.yml`'s notification-service security options.

## Engine detection

New file: `devcontainer/scripts/lib/engine.sh`, sourced by `ccc`, `ccc-code`,
`ccc-compose`, and `ccc-rebuild`.

- If `CLAUDE_DEVCONTAINER_ENGINE` is set (`docker` or `podman`), use it. If that binary
  isn't found, fail with a clear error — no silent fallback.
- Otherwise auto-detect: prefer `docker` if `command -v docker` succeeds and `docker
  info` responds (daemon reachable); else fall back to `podman` if present.
- If neither is found and no override is set, fail with a clear error pointing at the
  README setup section.

Detection re-runs on every script invocation (cheap: one `command -v` + one daemon
probe) rather than being cached/exported once, to avoid staleness if the user
installs/removes an engine mid-session.

`lib/engine.sh` exports:

- `ENGINE_BIN` — `docker` or `podman`.
- `COMPOSE_CMD` — `"$ENGINE_BIN compose"`. Podman's built-in `compose` subcommand
  (Podman 4.7+) is used; standalone `podman-compose` is not supported, and no fallback
  to it is attempted if `podman compose` fails.
- `COMPOSE_FILE` — path to `docker-compose.yml` under Docker, or
  `docker-compose.podman.yml` under Podman.

## Compose file split

`devcontainer/docker-compose.podman.yml` is a new, full standalone compose file (not a
merge override) containing only the `mcp-everything` service and the `mcp-net` network
declaration — `claude-desktop-notification` is omitted entirely. Podman runs are never
asked to bring up the notification service, rather than attempting it and hitting the
Docker-specific `apparmor:unconfined` security option or PulseAudio/D-Bus/rootless-
networking mismatches.

`docker-compose.yml` (Docker path) is unchanged.

## Script changes

- `ccc`, `ccc-rebuild`, `ccc-code`: source `lib/engine.sh`; replace
  `docker compose -f docker-compose.yml ...` with `$COMPOSE_CMD -f "$COMPOSE_FILE" ...`;
  add `--docker-path "$ENGINE_BIN"` to every `npx @devcontainers/cli` invocation (the
  CLI's documented mechanism for using a Docker-CLI-compatible alternate engine, which
  Podman is). No changes needed to `devcontainer.json` or `agent/Dockerfile`.
- `ccc-compose`: same substitution — `exec $COMPOSE_CMD -f "$COMPOSE_FILE" "$@"`.
- `ccc-code`: also sources `lib/engine.sh`; `docker ps -q --filter ...` becomes
  `$ENGINE_BIN ps -q --filter ...`, `docker inspect ...` becomes
  `$ENGINE_BIN inspect ...`. The VS Code attach URI logic downstream is unchanged and
  engine-agnostic.

## Notification service — scope

Out of scope, not best-effort. Under Podman, `claude-desktop-notification` is simply
never started (it's absent from `docker-compose.podman.yml`). No attempt is made to
port its AppArmor/PulseAudio/D-Bus/host-networking tricks to Podman's confinement and
rootless-networking model. Documented in README as a known limitation: desktop
notifications are Docker-only.

## Error handling

- `CLAUDE_DEVCONTAINER_ENGINE` set to an engine whose binary isn't installed: hard
  error naming the missing binary, no fallback to auto-detection.
- Neither `docker` nor `podman` found and no override set: hard error naming both
  options and pointing at the README setup section.

## README changes

- "System requirements": Docker **or** Podman 4.7+ (built-in `podman compose` support),
  removing the existing podman TODO line.
- Document the `CLAUDE_DEVCONTAINER_ENGINE` override and the auto-detection order.
- Add a "Known limitations" note: desktop notifications are Docker-only; not started
  under Podman.

## Testing

No CI in this repo; verification is manual, matching the existing project convention:

- Run `ccc` on a Docker host, confirm unchanged behavior (regression check).
- Run `ccc` on a machine/VM with only Podman installed: confirm the agent container
  comes up and drops into a shell, `mcp-everything` is reachable, and no notification
  container is started.
- Confirm `CLAUDE_DEVCONTAINER_ENGINE=docker` and `=podman` both force the expected
  engine when both are installed.
- Confirm `ccc-compose ps`/`ccc-code` work under both engines.

## Amendment (post-implementation)

Manual verification on a real Podman VM surfaced a wrong assumption above:
`podman compose` is **not** a self-contained implementation — it's a dispatcher that
shells out to an external compose provider (`docker-compose` CLI plugin,
`docker-compose` binary, or `podman-compose`), none of which Podman installs itself.
Without one present, `podman compose ...` fails with a 7-line "looking up compose
provider failed" error.

Fix: `lib/engine.sh` now runs `podman compose version` as a preflight check right
after selecting `ENGINE_BIN=podman`, and fails with an actionable error ("install
podman-compose") instead of letting the raw podman error surface later inside
`@devcontainers/cli`. `podman-compose` is now a documented required dependency
alongside Podman itself (README "Requirements").

A second Podman-only failure surfaced next: `devcontainer.json` bind-mounts
`${localEnv:HOME}/.netrc` unconditionally. Docker silently creates an empty file when a
bind-mount source doesn't exist on the host; Podman requires the source to pre-exist and
fails with `statfs: no such file or directory` otherwise. Fix: `ccc`, `ccc-code`, and
`ccc-rebuild` now bootstrap `~/.netrc` with `touch` if missing, the same pattern already
used for `~/.claude.json` just above it in each script.

A third issue: `podman-compose` 1.0.6 (the actual provider `podman compose` dispatches
to) doesn't support Docker Compose v2's `up --wait` flag and errors on it
("unrecognized arguments: --wait"). Neither compose file defines healthchecks, so
`--wait` doesn't buy meaningful readiness-waiting under Podman anyway. Fix:
`lib/engine.sh` now exports `COMPOSE_UP_FLAGS` (`-d --wait` for Docker, `-d` for
Podman), and `ccc`/`ccc-code`/`ccc-rebuild` use `up $COMPOSE_UP_FLAGS` instead of a
hardcoded `up -d --wait`.

A fourth issue: the agent container build failed on `FROM golang:1.24-alpine` with
`short-name "golang:1.24-alpine" did not resolve to an alias and no unqualified-search
registries are defined`. Docker always defaults short image names to `docker.io`;
Podman's short-name resolution depends on host config (`registries.conf` /
`shortnames.conf`), which varies by machine — `node:22-alpine` happened to resolve via
an existing alias, `golang:1.24-alpine` didn't. Fix: fully qualify every `FROM` in this
repo's Dockerfiles to `docker.io/library/...` (`agent/Dockerfile` — both the
`golang:1.24-alpine` builder stage and the `ubuntu:24.04` base,
`claude-desktop-notification/Dockerfile`, `mcp-everything/Dockerfile`). This removes
the dependency on host registry config entirely and is a no-op under Docker.
