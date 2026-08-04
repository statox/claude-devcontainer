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

# Allow dev to run mise with sudo
# Used in postCreate.sh to install system dependencies from repo's .mise.toml
RUN echo "dev ALL=(root) NOPASSWD:SETENV: /usr/local/bin/mise" > /etc/sudoers.d/dev-mise \
    && chmod 0440 /etc/sudoers.d/dev-mise

USER dev
WORKDIR /workdir

# Pre-create dirs owned by dev so named volumes mounted here inherit dev's
# ownership instead of being root-owned and unwritable.
RUN mkdir -p /home/dev/.config/glab-cli /home/dev/.claude /home/dev/.vscode-server

COPY --chown=${USER_UID}:${USER_GID} postCreate.sh /home/dev/postCreate.sh
RUN chmod 755 /home/dev/postCreate.sh
