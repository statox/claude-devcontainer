_This README.md was written by a human for other humans. When modifying it, try to keep a tidy writing and avoid novel-sized LLM generated paragraphs._

# Claude DevContainer

This repo is a collection of scripts to run Claude Code and its MCP servers in isolated containers.

- Run Claude Code in a dedicated container by host directory
- Run MCP servers as long-lived singletons - Allows isolated credential access
- Run VS Code Claude extension in the Claude container for easy VS Code integration
- Supports Docker and Podman runtimes

**Important** Not tested on MacOS yet. Tested exclusively on Ubuntu 24.

## Motivation

The goal is to allow users to safely run Claude Code and its MCP servers.

Security
- Restrict Claude Code container access to a single directory of the host
- Run MCP servers in dedicated isolated containers so that the MCP credentials are only available to the tools needing them
- Run dangerous tools (e.g. requiring access to host D-BUS) in isolated containers to limit the host

Developper experience
- Use standard tooling (devcontainers, docker/podman compose) to easily modify the setup
- Use versioned Claude customizations (`CLAUDE.md`, skill, MCP configurations)
- Automatically install marketplaces and plugins on launch
- Allow using Claude Code on the CLI or in VS Code extension

Exhaustive Claude Code configuration
- [`.claude/` configuration directory](https://code.claude.com/docs/en/settings)
- [Plugins](https://code.claude.com/docs/en/discover-plugins)
- Custom [hooks](https://code.claude.com/docs/en/hooks-guide)
- Custom [skills](https://code.claude.com/docs/en/skills)
- Secure [MCP](https://code.claude.com/docs/en/mcp-quickstart) integration

## Requirements

System requirements:

- `docker` with Compose v2, or `podman` 4.7+ **and** `podman-compose`
- `devcontainer` cli. See [devcontainers/cli](https://github.com/devcontainers/cli)
- If using VS Code:
    - The devcontainer extension installed (VS Code should prompt for installing it automatically)
    - The standard `xxd` utility

## Setup

1. Clone this repo anywhere, e.g.:
   ```sh
   git clone <this-repo-url> ~/claude_devcontainer
   ```
2. Add these two lines to your shell rc file (`~/.bashrc`, `~/.zshrc`):
   ```sh
   # Update the export to match the clone path
   export CLAUDE_DEVCONTAINER_HOME="$HOME/claude_devcontainer"
   source "$CLAUDE_DEVCONTAINER_HOME/shell-init.sh"
    # If you want to use podman instead of docker
   export CLAUDE_DEVCONTAINER_ENGINE='podman'
   ```
3. Open a new shell (or `source` your rc file). This defines the `ccc`,
   `ccc-code`, `ccc-compose`, and `ccc-rebuild` commands.

## How to use

Once you followed the setup:

- Navigate to any directory in your terminal
- Run `ccc` to open Claude CLI with the current directory mounted in the container
    - The first run requires to build the different Docker images which takes several minutes
- Run `ccc-code` to open VS Code with the Claude Code extension running in the container

After running `ccc` or `ccc-code` Docker (or Podman depending on you value of `CLAUDE_DEVCONTAINER_ENGINE`) should show several running containers:

- `devcontainer-mcp-*` for the different MCP containers
- `devcontainer-claude-desktop-notification` If using Docker on Linux
- `vsc-claude_devcontainer-[uuid]` for each directory where you ran `ccc`

In `vsc-claude_devcontainer-[uuid]` the current directory of the host is mounted to `/workdir` in the container.

To inspect/manage the singleton services without going through the full flow use the helper `ccc-compose`:

```shell
ccc-compose ps
ccc-compose logs -f
ccc-compose down
```

### Podman / Docker

The setup supports both Podman and Docker to run the containers.

The selection for the engine is as follow:

- Use Docker if its installed and its deamon is reachable
- Else use Podman if installed.

This can be overriden by setting the environment variable `CLAUDE_DEVCONTAINER_ENGINE` to either `docker` or `podman`


### CLI Usage

To use Claude Code as a cli you need to run `ccc`. This command creates the required containers and starts a new shell in the container running Claude Code.

Once the shell is open you need to run one of the following commands

```shell
claude  # Start the claude cli
cc      # Alias to `claude`
ccd     # Alias to `claude --dangerously-skip-permissions`
```

### VS Code usage

VS Code's Claude Code extension can run confined inside the agent container used by the CLI. Rather than the usual "Reopen in Container" flow (which expects a `.devcontainer/devcontainer.json` inside the repo), VS Code attaches to the container we create.

In a terminal navigate to the directory you want to use and run `ccc-code`. This opens VS Code UI.

The first time running this command VS Code might prompt you to install the Devcontainer extension and to trust the Claude extension which install automatically (See `customizations.vscode.extensions` in [`devcontainer.json`](./devcontainer/devcontainer.json).

And the bottom left of the UI you should see VS Code connected to a remote environment. The first time might take several minutes while the containers are being built.

**Warning** The VS Code integration relies on an undocumented feature. This might break in the future and would benefit from a stronger integation.

## Configuration

You can configure all the claude agents by editing the files in [`claude/`](./claude). All the files in this directory are symlinked by [`postCreate.sh`](./devcontainer/agent/postCreate.sh) to the container when it is created. Modifying this directory requires to run `ccc-rebuild` to get the changes in the containers.

- [`CLAUDE.md`](./claude/CLAUDE.md) is the user-scoped configuration Claude will always have in its context.
- [`settings.json`](./claude/settings.json) Claude's settings file (permissions, hooks, env variables, ...)
- [`skills/`](./claude/skills/) contains the skills you create
- [`plugins.json`](./claude/plugins.json) _This is a custom file for this repository._ The [`postCreate.sh`](./devcontainer/agent/postCreate.sh) reads this file and runs `claude plugin marketplace add ...` and `claude plugin install ... --scope user` for each entry so that Claude Code always has your configured plugins.
- [`mcp-servers.json`](./claude/mcp-servers.json) _This is a custom file for this repository._ The [`postCreate.sh`](./devcontainer/agent/postCreate.sh) reads this file and inject it into the container's `$HOME/.claude.json` file so that Claude Code always has your configured MCP servers.
- [`statusline-command.sh`](./claude/statusline-command.sh) This is the script which controls what the command line displays in the Claude Code cli. It is linked by the `statusLine` key in [`settings.json`](./claude/settings.json)
- [`notifications/`](./claude/notifications) This is a custom script used to allow Claude Code cli sending Desktop notifications on Linux. See the dedicated section in this README

When updating the setup you need to run `ccc-rebuild` to get the configurations included in the repo.

**Warning** `ccc-rebuild` closes your current containers. When developing on this repo you might want to have two local clones:

- One powering your current agent
- One running the developments, you can override you aliases and env variables to point to this directory in terminals where you do the testing.

This avoids the workflow where you start your agent in the container -> You make it change the repository -> You run `ccc-rebuild` which kills your agent -> But the changes broke the build and now you can't prompt your agent to fix the problem.

## MCP servers

This setup supports two different types of MCP servers "agent sidecar servers" and "isolated servers".

### Agent sidecar servers

These are MCP servers running directly in the container agent. For example LSP servers need to run this way because some of them need to be configured directly in the repo (e.g. The typescript LSP needs `node_modules` with typescript installed in the `/workdir`)

To expose LSP servers to Claude Code we use [mcp-language-server](https://github.com/isaacphi/mcp-language-server).

#### Installating a LSP Server as an agent sidecar server

- Update [`postCreate.sh`](./devcontainer/agent/postCreate.sh) to add the installation of the server
- Update [`mcp-servers.json`](./claude/mcp-servers.json) to make `mcp-language-server` expose the LSP

```json
  "python": {
    "command": "mcp-language-server",
    "args": ["--workspace", "/workdir", "--lsp", "pyright-langserver", "--", "--stdio"]
  }
```

### Isolated servers

These are MCP servers running in their own containers isolated from the Claude Code agent. They are used to provide access to external toolings requiring authentication and/or dansgerous tools requiring host access.

To allow the communication between the agent container and the MCP containers we use

- The [stdio transport](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports#stdio) capability of MCP servers
- The standard [`socat`](https://man7.org/linux/man-pages/man1/socat.1.html) utility to connect the agent stdout to the MCP server stdin

#### Installing an isolated MCP

- In [`devcontainer/`](./devcontainer) create a new directory to store the MCP container Docker file
- Create the new docker file
    ```
    # Install the MCP
    FROM docker.io/library/node:22-alpine
    RUN npm install -g @upstash/context7-mcp

    # Install socat
    RUN apk add --no-cache socat

    USER node

    # Expose the MCP server's port
    EXPOSE 3002

    # Use socat to create a new process with the MCP and write on its stdin
    CMD ["socat", "TCP-LISTEN:3002,fork,reuseaddr", "EXEC:context7-mcp"]
    ```
- Update [`docker-compose.yml`](./devcontainer/docker-compose.yml) and [`docker-compose.podman.yml`](./devcontainer/docker-compose.podman.yml) to include the new container to the setup.
- Update [`mcp-servers.json`](./claude/mcp-servers.json) to use `netcat` to send the MCP queries to the container's socat

```json
  "context7": {
    "command": "nc",
    "args": ["mcp-context7", "3002"]
  },
```

## System tools

To provide the agent with more system tools (`shellcheck`, `jq`, ...) you have two options:

- [Devcontainer features](https://containers.dev/features): The agent container is built with [`devcontainer.json`](./devcontainer/devcontainer.json), this allows to use standard features to add new tools (this is how we install `claude-code` or `uv` for example)
- [Dockerfile](./devcontainer/agent/Dockerfile): For tools which are not available as devcontainer features you can change the agent's Dockerfile which is applied after applying the devcontainer features. (This is how we install `glab` cli for example)


## Desktop notifications

This setup includes an experimental desktop notification feature. For now it works only on Linux+Docker.

### How it works

- The compose files spawn a `claude-desktop-notification` service defined in [`devcontainer/claude-desktop-notification`](./devcontainer/claude-desktop-notification)
- This services runs `socat` to listen to a Unix socket and pipe its connections to the [`handle-notify.sh`](./devcontainer/claude-desktop-notification/handle-notify.sh) script's stdin.
- [`handle-notify.sh`](./devcontainer/claude-desktop-notification/handle-notify.sh) does two things:
    - It plays [`bell.wav`](./claude/notifications/bell.wav) using PulseAudio via `paplay`
    - It runs a desktop notification with `notify-send`


On the agent side:
- [`settings.json`](./claude/settings.json) configures two hooks: `Notification` and `Stop` which make Claude call the script [`bell-notify.sh`](./claude/notifications/bell-notify.sh) when it is waiting for the user's input.
- [`bell-notify.sh`](./claude/notifications/bell-notify.sh) is symlinked at container creation with [`postCreate.sh`](./devcontainer/agent/postCreate.sh)
- When invoked `bell-notify.sh` uses `socat` to send a message to the `claude-desktop-notification` container which triggers the notification

To run `paplay` the service needs to access the D-BUS and PulseAudio deamons of the host, which requires tweaking its isolation in `docker-compose.yml` and mounting the daemons sockets to the container.

### Troubleshooting

If this is causing problems to you

- Remove the container from [`docker-compose.yml`](./devcontainer/docker-compose.yml) or [`docker-compose.podman.yml`](./devcontainer/docker-compose.podman.yml) 
- Remove the `hook` instructions from [`settings.json`](./claude/settings.json)
- Run `ccc-rebuild`

If this is still a problem, contact the author of this repo.


## TODO

### Long build time

The rebuild time can get fairly long:

- The agent image is built from `agent/Dockerfile`, then the devcontainers CLI layers the features from `devcontainer.json` on top.
- A simple change to the base image or to `postCreate.sh` triggers a full rebuild, which is slow because the feature layers get rebuilt too.

This is normal devcontainer behavior but can get annoying when iterating on this setup.

Reviewed options:

- **Local devcontainer feature.** The idea was to create a Devcontainer [local feature](https://containers.dev/implementors/features-distribution/#addendum-locally-referenced) in this repo and use it in [`devcontainer.json`](./devcontainer/devcontainer.json). That didn't work because local features must be part of the `.devcontainer` directory of the workdir (  [microsoft/vscode-remote-release#11356](https://github.com/microsoft/vscode-remote-release/issues/11356)) which isn't compatible with our centralized Devcontainer setup.

- **A base image split** The idea was to split `agent/Dockerfile` in two images to benefit from more caching. But this adds complexity to the build process and seems clunky


- **Getting rid of devcontainer altogether** The dev container setup makes it super easy to integrate in VS Code. We want to avoid ntegrating a bare container in VS Code manually.

### Reword configuration inclusion

For now the Claude Code configurations are included directly in this repo which isn't ideal for a collaborative setup where we want teammates to use this repo as a base -rarely modifying it- and allow them to have their own configurations stored in a separate dotfiles repo.
