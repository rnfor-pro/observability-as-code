#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# Grafana MCP — Dev Bootstrap Runbook
# Prereqs: kubectl pointed at dev cluster, docker, access to Artifactory
# Namespace: dev-keystone (assumed to exist already)
# ═══════════════════════════════════════════════════════════════════════════════

# ── STEP 0: Confirm context ──────────────────────────────────────────────────
kubectl config current-context
kubectl config set-context --current --namespace=dev-keystone


# ── STEP 1: Build & push the image ──────────────────────────────────────────
# Option A — let the GitHub Actions workflow do it (recommended):
#   Push a change to docker/grafana-mcp/Dockerfile on the develop branch.
#   The grafana-mcp-build-push.yaml workflow will build and push dev/non-prod/prod tags.
#
# Option B — build and push manually for the first time:

docker login docker.artifactory.<your-domain>.com

# Place your org CA cert at docker/grafana-mcp/certs/internal-ca.crt before building
cp /path/to/your/org-ca.crt docker/grafana-mcp/certs/internal-ca.crt

docker build \
  -t grafana-mcp:0.5.0 \
  docker/grafana-mcp/.

REGISTRY="docker.artifactory.<your-domain>.com"
REPO="<your-org>/obseng-keystone-infra/grafana-mcp/grafana-mcp_0.5.0"

docker tag grafana-mcp:0.5.0 $REGISTRY/$REPO:dev
docker push $REGISTRY/$REPO:dev


# ── STEP 2: Create the Artifactory image pull secret ────────────────────────
kubectl create secret docker-registry artifactory-pull-secret \
  --namespace dev-keystone \
  --docker-server=docker.artifactory.<your-domain>.com \
  --docker-username=<your-artifactory-username> \
  --docker-password=<your-artifactory-api-key>

# Verify
kubectl get secret artifactory-pull-secret -n dev-keystone


# ── STEP 3: Create the Grafana service account token secret ─────────────────
# In your dev Grafana:
#   Administration → Service Accounts → Add service account
#   Name: mcp-server-dev  |  Role: Viewer
#   Add token → copy value

kubectl create secret generic grafana-mcp-token \
  --namespace dev-keystone \
  --from-literal=GRAFANA_SERVICE_ACCOUNT_TOKEN='<paste-token-here>'

# Verify
kubectl describe secret grafana-mcp-token -n dev-keystone


# ── STEP 4: Apply all dev manifests ─────────────────────────────────────────
kubectl apply -n dev-keystone -f manifests/dev/serviceaccount.yaml
kubectl apply -n dev-keystone -f manifests/dev/configmap.yaml
kubectl apply -n dev-keystone -f manifests/dev/deployment.yaml
kubectl apply -n dev-keystone -f manifests/dev/service.yaml
kubectl apply -n dev-keystone -f manifests/dev/ingress.yaml
kubectl apply -n dev-keystone -f manifests/dev/hpa-pdb.yaml
kubectl apply -n dev-keystone -f manifests/dev/servicemonitor.yaml


# ── STEP 5: Verify ──────────────────────────────────────────────────────────
kubectl rollout status deployment/grafana-mcp -n dev-keystone --timeout=120s

kubectl get pods      -n dev-keystone -l app.kubernetes.io/name=grafana-mcp
kubectl get svc       -n dev-keystone -l app.kubernetes.io/name=grafana-mcp
kubectl get ingress   -n dev-keystone grafana-mcp-ingress
kubectl get cert      -n dev-keystone

# Watch logs
kubectl logs -n dev-keystone -l app.kubernetes.io/name=grafana-mcp --follow


# ── STEP 6: Smoke test (no ingress/DNS needed) ───────────────────────────────
kubectl port-forward -n dev-keystone svc/grafana-mcp 8080:80 &

curl -s http://localhost:8080/healthz
curl -s http://localhost:8080/mcp     # lists available MCP tools

# Test MCP → Grafana connectivity from inside the pod
POD=$(kubectl get pod -n dev-keystone -l app.kubernetes.io/name=grafana-mcp -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n dev-keystone $POD -- wget -qO- http://grafana.dev-keystone.svc.cluster.local:3000/api/health


# ── STEP 7: MCP client config (share with your org) ─────────────────────────
# Add to Claude Desktop / Cursor / VS Code MCP settings:
#
# {
#   "mcpServers": {
#     "grafana-dev": {
#       "type": "streamable-http",
#       "url": "https://mcp-grafana-dev.<your-domain>.com/mcp"
#     },
#     "grafana-np": {
#       "type": "streamable-http",
#       "url": "https://mcp-grafana-np.<your-domain>.com/mcp"
#     },
#     "grafana-prod": {
#       "type": "streamable-http",
#       "url": "https://mcp-grafana-prod.<your-domain>.com/mcp"
#     }
#   }
# }


# ── Non-prod deployment (once dev is verified) ───────────────────────────────
kubectl create secret docker-registry artifactory-pull-secret \
  --namespace np-keystone \
  --docker-server=docker.artifactory.<your-domain>.com \
  --docker-username=<your-artifactory-username> \
  --docker-password=<your-artifactory-api-key>

kubectl create secret generic grafana-mcp-token \
  --namespace np-keystone \
  --from-literal=GRAFANA_SERVICE_ACCOUNT_TOKEN='<np-grafana-token>'

kubectl apply -n np-keystone -f manifests/non-prod/


# ── Prod deployment ──────────────────────────────────────────────────────────
kubectl create secret docker-registry artifactory-pull-secret \
  --namespace prod-keystone \
  --docker-server=docker.artifactory.<your-domain>.com \
  --docker-username=<your-artifactory-username> \
  --docker-password=<your-artifactory-api-key>

kubectl create secret generic grafana-mcp-token \
  --namespace prod-keystone \
  --from-literal=GRAFANA_SERVICE_ACCOUNT_TOKEN='<prod-grafana-token>'

kubectl apply -n prod-keystone -f manifests/prod/
