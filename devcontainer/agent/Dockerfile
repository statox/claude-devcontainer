# Builds mcp-language-server (Go binary) in an isolated stage so it doesn't
# depend on the node feature, which is layered onto this image by the
# devcontainers CLI *after* this Dockerfile builds.
FROM docker.io/library/golang:1.24-alpine AS mcp-language-server-builder
RUN go install github.com/isaacphi/mcp-language-server@latest

FROM docker.io/library/ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    less \
    netcat-openbsd \
    openssh-client \
    ripgrep \
    shellcheck \
    socat \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Install the GitLab CLI (glab) from the official release .deb
ARG GLAB_VERSION=1.103.0
RUN curl -fsSL -o /tmp/glab.deb \
    "https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_VERSION}/downloads/glab_${GLAB_VERSION}_linux_amd64.deb" \
    && apt-get install -y --no-install-recommends /tmp/glab.deb \
    && rm -f /tmp/glab.deb /var/lib/apt/lists/* 2>/dev/null || true

COPY --from=mcp-language-server-builder /go/bin/mcp-language-server /usr/local/bin/mcp-language-server

# Create dev user with UID/GID matching the host user, passed in as build
# args (see scripts/lib/env.sh + devcontainer.json's build.args). This
# matters on macOS, where the default host user UID (501) differs from the
# Dockerfile's old hardcoded UID (1000): devcontainer CLI's
# updateRemoteUserUID remaps the user's UID *after* this image is built, but
# devcontainer features layered onto the image between build and remap (e.g.
# the claude-code feature) still run as the build-time UID. Anything they
# write under /tmp keyed to that UID (Claude Code itself namespaces scratch
# dirs as /tmp/claude-<uid>) becomes inaccessible once the remap changes the
# UID to something else — which is a no-op on most Linux hosts (UID 1000 by
# convention) but not on macOS, which is why this only broke there. Building
# with the correct UID/GID from the start avoids the remap entirely.
ARG USER_UID=1000
ARG USER_GID=1000
# ubuntu:24.04 ships a pre-existing "ubuntu" user/group at 1000:1000; userdel
# -r removes the user and its home dir but leaves the group behind, so it
# must be dropped too before a same-GID "dev" group can be created (the
# common case, since USER_GID defaults to 1000).
RUN userdel -r ubuntu 2>/dev/null || true
RUN groupdel ubuntu 2>/dev/null || true
RUN (getent group "$USER_GID" >/dev/null || groupadd -g "$USER_GID" dev) \
    && useradd -m -s /bin/bash -u "$USER_UID" -g "$USER_GID" dev

USER dev
WORKDIR /workdir

# Pre-create dirs owned by dev so named volumes mounted here inherit dev's
# ownership instead of being root-owned and unwritable.
RUN mkdir -p /home/dev/.config/glab-cli /home/dev/.claude /home/dev/.vscode-server

COPY --chown=dev:dev postCreate.sh /home/dev/postCreate.sh
RUN chmod 755 /home/dev/postCreate.sh
