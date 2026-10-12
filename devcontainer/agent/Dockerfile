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

# System packages ([bootstrap.packages], e.g. apt:...) need root and must run
# before /mise is handed to dev below, while /mise still only holds config -
# not yet the (large) tool installs, so there's nothing dev-owned to disturb.
RUN mise bootstrap packages apply --yes

# UID/GID mapping - devcontainer/scripts/lib/env.sh exports the host's
# DEV_UID/DEV_GID that we pass as args at build time
ARG USER_UID=1000
ARG USER_GID=1000
RUN (getent group "$USER_GID" >/dev/null || groupadd -g "$USER_GID" dev) \
    && useradd -m -s /bin/bash -u "$USER_UID" -g "$USER_GID" dev

# Hand /mise to dev before any [tools] are installed into it (still cheap -
# just config + package state so far), so both the agent's own tools below
# and, at runtime, the mounted repo's own mise.toml tools (installed by
# provision.sh) are written as dev from the start instead of installed as
# root and fixed up with a `chown -R` after the fact.
RUN chown -R "$USER_UID:$USER_GID" /mise

# Allow dev to run mise with sudo
# Used in provision.sh to install system dependencies from repo's .mise.toml
RUN echo "dev ALL=(root) NOPASSWD:SETENV: /usr/local/bin/mise" > /etc/sudoers.d/dev-mise \
    && chmod 0440 /etc/sudoers.d/dev-mise

USER dev
RUN mise install

WORKDIR /workdir

# Pre-create dirs owned by dev so named volumes mounted here inherit dev's
# ownership instead of being root-owned and unwritable.
RUN mkdir -p /home/dev/.config/glab-cli /home/dev/.claude /home/dev/.local/state/mise

COPY --chown=${USER_UID}:${USER_GID} provision.sh /home/dev/provision.sh
RUN chmod 755 /home/dev/provision.sh
