# grafana-mcp — Complete Deployment Runbook

> **Audience:** Platform engineers  
> **Chart:** `grafana-mcp` | **App version:** `0.11.0`  
> **Namespaces:** `dev-keystone` · `np-keystone` · `prod-keystone`

---

## Files you must change and what to change in each

Before running anything, open each file below and replace every placeholder:

### 1. `mcp-server/Dockerfile`
| Placeholder | Replace with |
|---|---|
| `ppa.<your-internal-domain>.com` | Your internal PPA hostname (from other Dockerfiles in your repo) |
| `<your-org>` (×2) | `sherwin-williams-co` |

### 2. `mcp-server/Chart.yaml`
| Placeholder | Replace with |
|---|---|
| `<your-org>` | `sherwin-williams-co` |

### 3. `mcp-server/values.yaml`
| Placeholder | Replace with |
|---|---|
| `docker.artifactory.<your-domain>.com` | Your Artifactory registry hostname |
| `<your-org>` in repository | `sherwin-williams-co` |
| `mcp-grafana-dev.<your-domain>.com` | Your actual internal domain for dev |

### 4. `mcp-server/ci/values-dev.yaml`
| Placeholder | Replace with |
|---|---|
| `docker.artifactory.<your-domain>.com` | Your Artifactory registry hostname |
| `<your-domain>.com` in host | Your actual internal domain |

### 5. `mcp-server/ci/values-non-prod.yaml` and `values-prod.yaml`
Same replacements as dev — just different env names in the host/tlsSecretName.

### 6. `.github/workflows/grafana-mcp-build-push.yaml`
| Placeholder | Replace with |
|---|---|
| `<your-org-actions-repo>` | Your org's actions repo (copy from `jfrog-build-push.yaml` line 17) |

---

## Repo structure

```
obseng-keystone-infra/
├── .github/
│   └── workflows/
│       └── grafana-mcp-build-push.yaml
└── mcp-server/
    ├── Dockerfile
    ├── Chart.yaml
    ├── values.yaml
    ├── ci/
    │   ├── values-dev.yaml
    │   ├── values-non-prod.yaml
    │   └── values-prod.yaml
    └── templates/
        ├── _helpers.tpl
        ├── configmap.yaml
        ├── deployment.yaml
        ├── hpa.yaml
        ├── ingress.yaml
        ├── pdb.yaml
        ├── secret.yaml
        ├── service.yaml
        ├── serviceaccount.yaml
        └── NOTES.txt
```

---

## Prerequisites

| Tool | Purpose |
|---|---|
| `kubectl` | Cluster interaction — must be pointed at target cluster |
| `helm` 3.12+ | Chart install / upgrade |
| Grafana UI access | Create service account tokens |
| ArgoCD access | GitOps promotion (Phase 2 only) |

```bash
# Confirm you are pointing at the right cluster before every operation
kubectl config current-context
kubectl config get-contexts

# Switch to dev cluster if needed
kubectl config use-context <dev-cluster-context>
```

---

## PHASE 1 — Local manual deployment (do this first)

### Step 1 — Create a Grafana service account token

Do this in the Grafana UI for the dev environment:

1. Open your dev Grafana: `https://grafana-dev.<your-domain>.com`
2. Go to **Administration → Service Accounts → Add service account**
3. Name: `mcp-server-dev` | Role: **Viewer**
4. Click **Add token** → **copy the token immediately** (shown once only)

---

### Step 2 — Bootstrap the token secret

This is the only secret ever created with `kubectl`. It is never committed to git.

```bash
kubectl create secret generic grafana-mcp-token \
  --namespace dev-keystone \
  --from-literal=GRAFANA_SERVICE_ACCOUNT_TOKEN='<paste-token-here>'

# Verify it was created
kubectl get secret grafana-mcp-token -n dev-keystone
kubectl describe secret grafana-mcp-token -n dev-keystone
```

---

### Step 3 — Dry run — render templates and inspect before installing

Always do this first. No resources are created.

```bash
# From the repo root
helm template grafana-mcp ./mcp-server \
  --namespace dev-keystone \
  -f mcp-server/ci/values-dev.yaml \
  --debug

# Lint the chart for errors
helm lint ./mcp-server -f mcp-server/ci/values-dev.yaml
```

Review the output. Check:
- Image reference matches your Artifactory path
- Grafana URL points to `grafana.dev-keystone.svc.cluster.local:3000`
- Ingress host matches your internal domain
- `--disable-write` is present in the args

---

### Step 4 — Install the chart into dev-keystone

```bash
helm upgrade --install grafana-mcp ./mcp-server \
  --namespace dev-keystone \
  --create-namespace \
  -f mcp-server/ci/values-dev.yaml \
  --wait \
  --timeout 3m
```

---

### Step 5 — Verify the deployment

```bash
# Rollout status
kubectl rollout status deployment/grafana-mcp \
  -n dev-keystone --timeout=120s

# Check pods are Running
kubectl get pods -n dev-keystone \
  -l app.kubernetes.io/name=grafana-mcp

# Check all chart resources
kubectl get all -n dev-keystone \
  -l app.kubernetes.io/name=grafana-mcp

# Check ingress has an address and TLS cert was issued
kubectl get ingress -n dev-keystone grafana-mcp-ingress
kubectl get certificate -n dev-keystone

# Follow live logs
kubectl logs -n dev-keystone \
  -l app.kubernetes.io/name=grafana-mcp \
  --follow
```

---

### Step 6 — Local smoke test (no DNS required)

```bash
# Port-forward the service to your local machine
kubectl port-forward -n dev-keystone svc/grafana-mcp 8080:80

# In a second terminal:

# 1. Health check
curl -s http://localhost:8080/healthz

# 2. List available MCP tools
curl -s http://localhost:8080/mcp

# 3. Verify MCP can reach Grafana from inside the pod
POD=$(kubectl get pod -n dev-keystone \
  -l app.kubernetes.io/name=grafana-mcp \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n dev-keystone $POD -- \
  wget -qO- http://grafana.dev-keystone.svc.cluster.local:3000/api/health
```

Expected responses:
- `/healthz` → `{"status":"ok"}`
- `/mcp` → JSON list of available tools
- Grafana health → `{"database": "ok"}`

---

### Step 7 — Local MCP client configuration (for your machine only)

While port-forwarding is active (`kubectl port-forward ... 8080:80`),
configure your local AI client to use the local endpoint.

**Claude Desktop** — edit `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS)
or `%APPDATA%\Claude\claude_desktop_config.json` (Windows):

```json
{
  "mcpServers": {
    "grafana-dev-local": {
      "type": "streamable-http",
      "url": "http://localhost:8080/mcp"
    }
  }
}
```

**Cursor** — edit `.cursor/mcp.json` in your home directory:

```json
{
  "mcpServers": {
    "grafana-dev-local": {
      "type": "streamable-http",
      "url": "http://localhost:8080/mcp"
    }
  }
}
```

**VS Code** — edit `.vscode/mcp.json` in your workspace:

```json
{
  "servers": {
    "grafana-dev-local": {
      "type": "streamable-http",
      "url": "http://localhost:8080/mcp"
    }
  }
}
```

Restart your AI client after saving. The port-forward must be running
for the local config to work.

---

## PHASE 2 — Push to GitHub and deploy via ArgoCD

Only proceed to this phase once Phase 1 is fully working end-to-end.

---

### Step 8 — Build and push the image via GitHub Actions

```bash
# Commit both the Dockerfile and the workflow together
git add mcp-server/Dockerfile
git add .github/workflows/grafana-mcp-build-push.yaml
git commit -m "feat: add grafana-mcp server image and build workflow"
git push origin develop
```

Go to **GitHub → Actions → Build, Push & Retrieve Grafana MCP Image To/From JFrog**
and confirm the workflow completes successfully. It will:
1. Build the image from `mcp-server/Dockerfile`
2. Push three tags to Artifactory: `dev`, `non-prod`, `prod`
3. Commit `images.csv` back to the repo

---

### Step 9 — Push the Helm chart to GitHub

```bash
git add mcp-server/Chart.yaml
git add mcp-server/values.yaml
git add mcp-server/ci/
git add mcp-server/templates/
git commit -m "feat: add grafana-mcp helm chart"
git push origin develop
```

---

### Step 10 — Pre-create secrets in all namespaces before ArgoCD syncs

ArgoCD will not create secrets — they must exist before the first sync.

```bash
# NON-PROD — create token in np Grafana UI first (same steps as Step 1)
kubectl create secret generic grafana-mcp-token \
  --namespace np-keystone \
  --from-literal=GRAFANA_SERVICE_ACCOUNT_TOKEN='<np-token>'

# PROD — create token in prod Grafana UI first
kubectl create secret generic grafana-mcp-token \
  --namespace prod-keystone \
  --from-literal=GRAFANA_SERVICE_ACCOUNT_TOKEN='<prod-token>'

# Confirm all three namespaces have the secret
kubectl get secret grafana-mcp-token -n dev-keystone
kubectl get secret grafana-mcp-token -n np-keystone
kubectl get secret grafana-mcp-token -n prod-keystone
```

---

### Step 11 — Apply ArgoCD Application manifests

```bash
kubectl apply -f argocd/grafana-mcp-dev.yaml
kubectl apply -f argocd/grafana-mcp-np.yaml
kubectl apply -f argocd/grafana-mcp-prod.yaml
```

Watch ArgoCD sync:

```bash
# Check sync status
kubectl get applications -n argocd | grep grafana-mcp

# Watch events
kubectl describe application grafana-mcp-dev -n argocd
```

From the ArgoCD UI: confirm each app shows **Synced** and **Healthy**.

---

### Step 12 — Org-wide MCP client configuration

Once ArgoCD has deployed and ingress DNS is resolving, share this file
with everyone in your organisation. Save it as `grafana-mcp-config.json`.

**For all AI clients (Claude Desktop / Cursor / VS Code):**

```json
{
  "mcpServers": {
    "grafana-dev": {
      "type": "streamable-http",
      "url": "https://mcp-grafana-dev.<your-domain>.com/mcp"
    },
    "grafana-np": {
      "type": "streamable-http",
      "url": "https://mcp-grafana-np.<your-domain>.com/mcp"
    },
    "grafana-prod": {
      "type": "streamable-http",
      "url": "https://mcp-grafana-prod.<your-domain>.com/mcp"
    }
  }
}
```

Tell users to add the block for the environment they need to their client config:
- **Claude Desktop:** `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Cursor:** `~/.cursor/mcp.json`
- **VS Code:** `.vscode/mcp.json` in their workspace

---

## Useful debugging commands

```bash
# Describe pod — check Events section for scheduling / image pull errors
kubectl describe pod -n dev-keystone \
  -l app.kubernetes.io/name=grafana-mcp

# Check injected env vars (token is redacted by Kubernetes — expected)
kubectl exec -n dev-keystone $POD -- \
  env | grep -E 'GRAFANA|MCP|LOG'

# Check HPA
kubectl get hpa -n dev-keystone grafana-mcp-hpa

# Check PDB
kubectl get pdb -n dev-keystone grafana-mcp-pdb

# Check deployed Helm values
helm get values grafana-mcp -n dev-keystone

# Full Helm release history
helm history grafana-mcp -n dev-keystone

# Rollback to previous Helm release
helm rollback grafana-mcp -n dev-keystone
```

---

## Rotating the Grafana service account token

```bash
# 1. Generate a new token in the Grafana UI
#    Administration → Service Accounts → mcp-server-dev → Add token

# 2. Delete and recreate the secret
kubectl delete secret grafana-mcp-token -n dev-keystone
kubectl create secret generic grafana-mcp-token \
  --namespace dev-keystone \
  --from-literal=GRAFANA_SERVICE_ACCOUNT_TOKEN='<new-token>'

# 3. Restart pods to pick up the new secret
kubectl rollout restart deployment/grafana-mcp -n dev-keystone

# 4. Confirm rollout completes cleanly
kubectl rollout status deployment/grafana-mcp -n dev-keystone
```

---

## Uninstall

```bash
# Remove the Helm release
# The token secret is preserved by design (helm.sh/resource-policy: keep)
helm uninstall grafana-mcp -n dev-keystone

# Remove the secret manually if you want a full clean-up
kubectl delete secret grafana-mcp-token -n dev-keystone
```
