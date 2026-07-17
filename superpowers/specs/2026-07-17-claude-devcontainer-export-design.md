# Design: Extract `claude_devcontainer` from `dotfiles_statox`

## Goal

Move the "Claude Code devcontainer" feature (currently living under
`dotfiles_statox/devcontainer/` and `dotfiles_statox/claude/`) into its own
standalone, minimal repository (`claude_devcontainer`) that anyone can clone
and use — not just the original author's machine.

Constraints from the requester:
- No mentions of the term "dotfiles" anywhere in the new repo.
- The `claude/` directory of opinionated Claude Code configuration (CLAUDE.md,
  settings.json, hooks, statusline, skills) moves in as-is for now — it's not
  being genericized away yet, just de-personalized enough to read as shipped
  default config rather than one person's literal personal rules.
- Keep the new repo minimal: only what's needed to run the current feature
  set, with light cleanup opportunistically applied during the move.

## Source feature summary

Two containers, two lifecycles, run via the `devcontainers` CLI + Docker
Compose:
- `agent` — per-repo container (one per workspace folder) that Claude Code
  actually runs in. Built from `agent/Dockerfile`, configured via
  `devcontainer.json`, provisioned via `postCreate.sh` (symlinks Claude Code
  config in, merges MCP server config into `~/.claude.json`, installs
  required plugins, installs `typescript-language-server`).
- `broker` — a global singleton container with host PulseAudio/D-Bus access,
  relays desktop notifications (sound + `notify-send`) from the agent
  container over a Unix socket volume, since the agent container itself has
  no host access.
- `mcp-everything` — a singleton container running an MCP test server,
  reached over a dedicated `mcp-net` bridge network.
- Host-side scripts wrap the whole flow into one command that brings up the
  singleton services and drops the user into a shell in their repo's agent
  container.

## New repo layout

```
claude_devcontainer/
├── README.md
├── LICENSE                          (MIT)
├── shell-init.sh                    <- sourced from the user's shell rc; defines aliases
├── devcontainer/
│   ├── devcontainer.json
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
    └── skills/repo-onboarding/{SKILL.md, REPO_OVERVIEW_template.md}
```

Everything not listed above (dotfiles-management scripts, `REPO_OVERVIEW.md`,
git hooks, unrelated dotfiles) is left behind — out of scope for this
feature.

## Path resolution: `CLAUDE_DEVCONTAINER_HOME`

Today every script and config hardcodes `$HOME/.dotfiles/devcontainer` and
`$HOME/.dotfiles/claude`. The new repo can be cloned anywhere, so a single
env var, `CLAUDE_DEVCONTAINER_HOME`, set once by the user in their shell rc
file, replaces every one of those references:

- `devcontainer.json`'s bind mount uses `${localEnv:CLAUDE_DEVCONTAINER_HOME}`
  (the devcontainers CLI supports this substitution natively), mounted into
  the container at `/home/dev/.claude-devcontainer` (replacing today's
  `/home/dev/.dotfiles` mount). `postCreate.sh` reads `claude/*` from
  `~/.claude-devcontainer/claude` instead of `~/.dotfiles/claude`.
- `docker-compose.yml`'s broker asset mount becomes
  `${CLAUDE_DEVCONTAINER_HOME}/claude:/claude-assets:ro`.
- All four scripts (`ccc`, `ccc-compose`, `ccc-rebuild`, `ccc-code`) resolve
  `DOTFILES_DEVCONTAINER_DIR`-equivalent paths from
  `$CLAUDE_DEVCONTAINER_HOME/devcontainer` instead of
  `$HOME/.dotfiles/devcontainer`. Scripts fail fast with a clear error if the
  env var is unset.

No installer script writes to the user's shell rc automatically. The README
documents the two lines to add:

```sh
export CLAUDE_DEVCONTAINER_HOME="$HOME/path/to/claude_devcontainer"
source "$CLAUDE_DEVCONTAINER_HOME/shell-init.sh"
```

`shell-init.sh` defines the four aliases (`ccc`, `ccc-compose`,
`ccc-rebuild`, `ccc-code`) pointing at
`$CLAUDE_DEVCONTAINER_HOME/devcontainer/scripts/*`.

## Command renaming

The host-side entry point `claude` (today's alias, which shadows the real
`claude` CLI binary and is confusing for a general-purpose repo) is renamed
to `ccc` ("Claude Code Container"). The other scripts are renamed to match:

| Old | New |
|---|---|
| `claude-devcontainer` | `ccc` |
| `claude-devcontainer-compose` | `ccc-compose` |
| `claude-devcontainer-rebuild` | `ccc-rebuild` |
| `code-devcontainer` | `ccc-code` |

All comments and README references updated to match. The Claude Code binary
itself is unaffected — it's still invoked as `claude` from *inside* the
agent container shell, same as today.

## Cleanup during migration

- **Drop the nvm lazy-load workaround.** The scripts today special-case
  loading `nvm` because the old alias was literally named `claude`, which
  shadowed the zsh nvm plugin's lazy `npx` stub. Renaming to `ccc` removes
  the shadowing conflict, so this workaround's premise no longer applies.
  `npx`/Node being available on PATH becomes a plain documented prerequisite.
- **Remove all "dotfiles" wording.** Every comment, README section, and
  architecture diagram referencing `~/.dotfiles/...` or "the dotfiles repo"
  is rewritten in terms of `$CLAUDE_DEVCONTAINER_HOME` / "this repo".
- **`CLAUDE.md` heading.** "Personal Global Rules (Active Everywhere)"
  becomes "Default Global Rules (Active Everywhere)" — wording only, all
  actual rules/content unchanged. This is opinionated starter config anyone
  cloning the repo can edit or delete; it just shouldn't read as literally
  one specific person's identity.
- Everything else under `claude/` (settings.json, hooks, statusline,
  `mcp-servers.json`, `plugins.json`, skills) copies over unchanged — no
  machine-specific values were found in them.

## Explicitly out of scope / deferred

- **Notifications remain Linux + PulseAudio/D-Bus only**, exactly as today
  (`apparmor:unconfined`, `/run/user/$UID` host mounts). No cross-platform
  abstraction is being built now. The README adds a TODO: a future version
  should rename the `broker` service to something like
  `linux-desktop-notifications` and make it opt-in via a setting, rather than
  always brought up automatically, so the setup degrades gracefully on hosts
  without a Linux desktop session.
- **`claude/` is not being genericized** beyond the heading change above —
  it stays opinionated config, to be revisited later per the requester.
- No CI, no test suite, no packaging beyond what exists today — matches the
  "minimal repo" goal.

## Verification approach

After migration, run `ccc` from a scratch test repo (with
`CLAUDE_DEVCONTAINER_HOME` set to the new repo's clone path) and confirm:
- the singleton services (`broker`, `mcp-everything`) come up via
  `ccc-compose`;
- the agent container builds and `ccc` drops into a shell in it;
- `~/.claude` inside the container is populated via symlinks from
  `claude/*`;
- a notification hook fires an audible/visible notification on the host.
