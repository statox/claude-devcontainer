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

RUN mkdir -p /run/claude-desktop-notification && chmod 777 /run/claude-desktop-notification

CMD ["socat", "UNIX-LISTEN:/run/claude-desktop-notification/notify.sock,fork,unlink-early,mode=777", "EXEC:/usr/local/bin/handle-notify.sh"]
