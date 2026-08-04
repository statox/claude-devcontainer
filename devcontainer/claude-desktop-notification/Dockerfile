FROM docker.io/library/ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    dbus \
    libnotify-bin \
    pulseaudio-utils \
    socat \
    util-linux \
    && rm -rf /var/lib/apt/lists/*

COPY handle-notify.sh /usr/local/bin/handle-notify.sh
RUN chmod 755 /usr/local/bin/handle-notify.sh

# UID/GID mapping - devcontainer/scripts/lib/env.sh exports the host's
# DEV_UID/DEV_GID that we pass as args at build time
ARG USER_GID=1000
RUN mkdir -p /run/claude-desktop-notification \
    && chgrp "$USER_GID" /run/claude-desktop-notification \
    && chmod 770 /run/claude-desktop-notification

CMD ["socat", "UNIX-LISTEN:/run/claude-desktop-notification/notify.sock,fork,unlink-early,mode=660", "EXEC:/usr/local/bin/handle-notify.sh"]
