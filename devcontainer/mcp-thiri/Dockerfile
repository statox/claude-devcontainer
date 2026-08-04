FROM docker.io/library/node:22-alpine

RUN apk add --no-cache socat

RUN npm install -g @bluesprincemedia/thiri-mcp

# UID/GID mapping - devcontainer/scripts/lib/env.sh exports the host's
# DEV_UID/DEV_GID that we pass as args at build time
ARG USER_UID=1000
ARG USER_GID=1000
RUN deluser node 2>/dev/null || true \
    && delgroup node 2>/dev/null || true \
    && addgroup -g "${USER_GID}" dev \
    && adduser -D -u "${USER_UID}" -G dev dev

RUN mkdir -p /run/mcp-thiri && chown dev:dev /run/mcp-thiri && chmod 770 /run/mcp-thiri

USER dev

CMD ["socat", "UNIX-LISTEN:/run/mcp-thiri/mcp.sock,mode=660,fork,unlink-early", "EXEC:thiri-mcp"]
