# ─── Stage 1: cert ───────────────────────────────────────────────────────────
# Downloads your org's internal CA chain from the internal PPA server.
# Matches your org's standard Dockerfile pattern exactly (Alpine variant).
FROM alpine:latest as cert

RUN apk --update add bash ca-certificates curl && \
    curl http://ppa.<your-internal-domain>.com/certs/ca/keyfactorswroot \
         -o /usr/local/share/ca-certificates/swroot.crt && \
    curl https://ppa.<your-internal-domain>.com/certs/ca/chain \
         -o /usr/local/share/ca-certificates/sw-internal-chain.crt && \
    update-ca-certificates

# ─── Stage 2: app ────────────────────────────────────────────────────────────
# Pulls the official Grafana MCP server image from the public registry.
# Replace the ARG default if your org mirrors public images through Artifactory.
ARG BASE_IMAGE

# public_org          = grafana
# public_image_name   = mcp-grafana
# public_image_version= 0.5.0
FROM grafana/mcp-grafana:0.10.0-alpine

# ── OCI labels — parsed by the grafana-mcp-build-push.yaml workflow ──────────
# Label 1: image name  → extracted as IMAGE_NAME  by the workflow
LABEL org.opencontainers.image.title="grafana-mcp"
# Label 2: image version → extracted as IMAGE_VERSION by the workflow
LABEL org.opencontainers.image.version="0.10.0-alpine"
LABEL org.opencontainers.image.description="Grafana MCP Server — org wrapper image"
LABEL org.opencontainers.image.source="https://github.com/<your-org>/obseng-keystone-infra"
LABEL org.opencontainers.image.vendor="<your-org>"

# ── Copy internal CA certs from the cert stage ────────────────────────────────
# Same COPY --from=cert pattern as every other service in your org.
# No volume mounts needed — CA is baked into the image layer.
USER root
COPY --from=cert /usr/local/share/ca-certificates/swroot.crt \
                  /etc/ssl/certs/swroot.crt
COPY --from=cert /usr/local/share/ca-certificates/sw-internal-chain.crt \
                  /etc/ssl/certs/sw-internal-chain.crt

# Drop back to non-root — required by securityContext.runAsUser: 65534 in the Deployment
USER 65534

# Entrypoint and CMD are inherited from grafana/mcp-grafana upstream.
# Args (--disable-write, --metrics etc.) are passed via Deployment manifest.
EXPOSE 8080 9090