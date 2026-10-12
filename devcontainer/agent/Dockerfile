FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update  \
    && apt-get -y --no-install-recommends install  \
        curl git ca-certificates build-essential \
    && rm -rf /var/lib/apt/lists/*

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV MISE_DATA_DIR="/mise"
ENV MISE_CONFIG_DIR="/mise"
ENV MISE_CACHE_DIR="/mise/cache"
ENV MISE_INSTALL_PATH="/usr/local/bin/mise"
# Paranoid mode: repo configs need explicit trust.
# Trust is tied to file content. Editing a config revokes it.
# See https://mise.jdx.dev/paranoid.html
ENV MISE_PARANOID="1"
ENV PATH="/mise/shims:$PATH"
# ENV MISE_VERSION="..."

RUN curl https://mise.run | sh

COPY mise.toml /mise/config.toml

# Install system packages as root, before /mise is handed to dev.
RUN mise bootstrap packages apply --yes

# UID/GID mapping: env.sh passes the host's DEV_UID/DEV_GID as build args.
# Rename the base image's "ubuntu" user to "dev" with these ids.
# Drop its supplementary groups.
ARG USER_UID=1000
ARG USER_GID=1000
RUN groupmod -n dev -g "$USER_GID" ubuntu \
    && usermod -l dev -u "$USER_UID" -d /home/dev -m -G "" ubuntu

# dev owns /mise. All tools install as dev.
RUN chown -R "$USER_UID:$USER_GID" /mise

# Root provisioning script. The host scripts run it as root.
# dev has no sudo and can't edit it.
COPY provision-root.sh /usr/local/sbin/provision-root.sh
RUN chmod 755 /usr/local/sbin/provision-root.sh

USER dev

# Create dirs owned by dev. New volumes mounted here inherit this ownership.
RUN mkdir -p /home/dev/.config/glab-cli /home/dev/.claude /home/dev/.local/state/mise

RUN mise install

WORKDIR /workdir

COPY --chown=${USER_UID}:${USER_GID} provision.sh /home/dev/provision.sh
RUN chmod 755 /home/dev/provision.sh
