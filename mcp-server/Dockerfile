# ─── Stage 1: cert ────────────────────────────────────────────────────────────
FROM alpine:latest AS cert

RUN apk --update add bash ca-certificates curl && \
    curl http://ppa.<your-internal-domain>.com/certs/ca/keyfactorswroot \
         -o /usr/local/share/ca-certificates/swroot.crt && \
    curl https://ppa.<your-internal-domain>.com/certs/ca/chain \
         -o /usr/local/share/ca-certificates/sw-internal-chain.crt && \
    update-ca-certificates

# ─── Stage 2: app ─────────────────────────────────────────────────────────────
FROM grafana/mcp-grafana:0.10.0-alpine

LABEL org.opencontainers.image.title="grafana-mcp"
LABEL org.opencontainers.image.version="0.10.0-alpine"
LABEL org.opencontainers.image.description="Grafana MCP Server — org wrapper image"
LABEL org.opencontainers.image.source="https://github.com/<your-org>/obseng-keystone-infra"
LABEL org.opencontainers.image.vendor="<your-org>"

USER root

COPY --from=cert /usr/local/share/ca-certificates/swroot.crt \
                 /etc/ssl/certs/swroot.crt
COPY --from=cert /usr/local/share/ca-certificates/sw-internal-chain.crt \
                 /etc/ssl/certs/sw-internal-chain.crt

USER 65534

EXPOSE 8080 9090