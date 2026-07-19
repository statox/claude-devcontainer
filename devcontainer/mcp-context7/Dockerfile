FROM docker.io/library/node:22-alpine

RUN apk add --no-cache socat

RUN npm install -g @upstash/context7-mcp

# node:22-alpine already ships a non-root "node" user at uid 1000 for this
# purpose, so there's no need to create a separate one.
USER node

EXPOSE 3002
CMD ["socat", "TCP-LISTEN:3002,fork,reuseaddr", "EXEC:context7-mcp"]
