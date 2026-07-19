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
