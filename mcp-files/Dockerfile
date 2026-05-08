FROM grafana/mcp-grafana:0.5.0

# ── OCI Image Labels (parsed by jfrog-build-push.yaml workflow) ──────────────
# The workflow extracts these via: awk '/^LABEL/ { $1=""; print substr($0,2) }'
LABEL org.opencontainers.image.title="grafana-mcp"
LABEL org.opencontainers.image.version="0.5.0"
LABEL org.opencontainers.image.description="Grafana MCP Server — org wrapper image"
LABEL org.opencontainers.image.source="https://github.com/<your-org>/obseng-keystone-infra"
LABEL org.opencontainers.image.vendor="<your-org>"

# ── Bake in the org internal CA (same pattern as all other services) ──────────
# Copy the CA bundle from the build context.
# In CI the workflow checks out the repo; place your CA at:
#   docker/grafana-mcp/certs/internal-ca.crt
# (or adjust COPY path to wherever your org stores it in the repo)
USER root

COPY certs/internal-ca.crt /usr/local/share/ca-certificates/internal-ca.crt
RUN update-ca-certificates

# Drop back to the non-root user from the upstream image
USER 10001

# Expose MCP streamable-http port and metrics port
EXPOSE 8080 9090

# Entrypoint is inherited from upstream grafana/mcp-grafana image
# Args are passed in via Deployment manifest (args: [...])
