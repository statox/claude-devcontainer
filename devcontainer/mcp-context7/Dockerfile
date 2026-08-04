FROM docker.io/library/node:22-alpine

RUN apk add --no-cache socat

RUN npm install -g @upstash/context7-mcp

# Match the UID/GID of the host user (passed in as build args, see
# scripts/lib/env.sh + docker-compose.yml's build.args) so the unix socket
# shared with the agent container (mounted at the same UID/GID) can be
# mode 660 instead of world-accessible.
ARG USER_UID=1000
ARG USER_GID=1000
RUN deluser node 2>/dev/null || true \
    && delgroup node 2>/dev/null || true \
    && addgroup -g "${USER_GID}" dev \
    && adduser -D -u "${USER_UID}" -G dev dev


RUN mkdir -p /run/mcp-context7 && chown dev:dev /run/mcp-context7 && chmod 770 /run/mcp-context7

USER dev

CMD ["socat", "UNIX-LISTEN:/run/mcp-context7/mcp.sock,mode=660,fork,unlink-early", "EXEC:context7-mcp"]
