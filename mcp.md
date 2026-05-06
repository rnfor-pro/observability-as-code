Correct — for your setup:

```text
Grafana StatefulSet pod: grafana-statefulset-0
Grafana container name: grafana
Grafana service name: grafana-service
Namespace: np-keystone
Grafana MCP service: grafana-mcp
No NetworkPolicy
No JFrog imagePullSecret
ArgoCD already watches the repo
```

The MCP server should connect to **Grafana through the Kubernetes Service**, not directly to the pod. So your Grafana URL should be:

```text
http://grafana-service.np-keystone.svc.cluster.local:3000
```

Grafana MCP authenticates to Grafana using `GRAFANA_URL` and `GRAFANA_SERVICE_ACCOUNT_TOKEN`; Grafana recommends using a service account token for this. ([Grafana Labs][1])

---

# 1. Command to confirm your Grafana URL

Run:

```bash
kubectl get svc grafana-service -n np-keystone \
  -o jsonpath='http://{.metadata.name}.{.metadata.namespace}.svc.cluster.local:{.spec.ports[0].port}{"\n"}'
```

Expected output:

```text
http://grafana-service.np-keystone.svc.cluster.local:3000
```

Test Grafana from inside the namespace:

```bash
kubectl run grafana-url-test \
  -n np-keystone \
  --rm -it \
  --image=curlimages/curl \
  --restart=Never \
  -- curl -I http://grafana-service.np-keystone.svc.cluster.local:3000
```

Because your Grafana pod has multiple containers, use `-c grafana` when checking Grafana logs:

```bash
kubectl logs grafana-statefulset-0 -n np-keystone -c grafana --tail=100
```

---

# 2. Final folder structure

Put this folder inside the GitHub repo path that ArgoCD already watches.

```text
obseng-keystone-infra/
└── grafana-mcp/
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
        ├── _helpers.tpl
        ├── serviceaccount.yaml
        ├── deployment.yaml
        └── service.yaml
```

Keep this file **outside GitHub**:

```text
grafana-mcp-secrets.yaml
```

---

# 3. What each file does

## `Chart.yaml`

This tells Helm that `grafana-mcp/` is a Helm chart. ArgoCD sees this file and knows the folder can be rendered as Kubernetes manifests.

## `values.yaml`

This is your main configuration file. It controls the image, Grafana URL, secret name, service port, CPU/memory, and MCP safety flags.

## `_helpers.tpl`

This contains reusable Helm naming and label logic. It keeps names and labels consistent across the Deployment, Service, and ServiceAccount.

## `serviceaccount.yaml`

This creates a Kubernetes ServiceAccount for the MCP pod. This is **not** the Grafana service account. It is only the Kubernetes identity for the pod.

## `deployment.yaml`

This creates the actual Grafana MCP pod. It defines the container image, command-line arguments, environment variables, health checks, security settings, and secret reference.

## `service.yaml`

This creates an internal Kubernetes ClusterIP Service so the MCP pod has a stable DNS name:

```text
http://grafana-mcp.np-keystone.svc.cluster.local:8000
```

## `grafana-mcp-secrets.yaml`

This creates the Kubernetes Secret holding the Grafana service account token. Do **not** commit it to GitHub.

---

# 4. Create the Helm chart files

Run this from your repo root:

```bash
mkdir -p grafana-mcp/templates
```

---

## File 1: `grafana-mcp/Chart.yaml`

```bash
cat > grafana-mcp/Chart.yaml <<'EOF'
apiVersion: v2
name: grafana-mcp
description: Internal Helm chart for Grafana MCP Server in np-keystone
type: application
version: 0.1.0
appVersion: "0.13.1"
EOF
```

### What each block does

```yaml
apiVersion: v2
```

Uses Helm chart API version 2.

```yaml
name: grafana-mcp
```

The name of this Helm chart.

```yaml
description: Internal Helm chart for Grafana MCP Server in np-keystone
```

Human-readable description.

```yaml
type: application
```

Tells Helm this chart deploys an application.

```yaml
version: 0.1.0
```

Version of your internal Helm chart.

```yaml
appVersion: "0.13.1"
```

Version of the Grafana MCP application/image you intend to run.

---

## File 2: `grafana-mcp/values.yaml`

Replace:

```text
YOUR_JFROG_REGISTRY
```

with your real JFrog registry.

```bash
cat > grafana-mcp/values.yaml <<'EOF'
replicaCount: 1

image:
  registry: YOUR_JFROG_REGISTRY
  repository: cso/obseng-keystone-infra/grafana/mcp-grafana
  tag: "0.13.1"
  pullPolicy: IfNotPresent

nameOverride: ""
fullnameOverride: ""

namespace: np-keystone

grafana:
  url: "http://grafana-service.np-keystone.svc.cluster.local:3000"
  tokenSecretName: grafana-mcp-token
  tokenSecretKey: token

serviceAccount:
  create: true
  name: grafana-mcp
  automountServiceAccountToken: false

podAnnotations: {}

podLabels:
  app.kubernetes.io/part-of: keystone-pipeline
  app.kubernetes.io/component: grafana-mcp

service:
  type: ClusterIP
  port: 8000
  targetPort: 8000

mcp:
  args:
    - "-t"
    - "streamable-http"
    - "--address"
    - "0.0.0.0:8000"
    - "--endpoint-path"
    - "/mcp"
    - "--log-level"
    - "info"
    - "--max-loki-log-limit"
    - "100"

    # Safety controls
    - "--disable-write"
    - "--disable-admin"
    - "--disable-incident"
    - "--disable-oncall"
    - "--disable-alerting"
    - "--disable-sift"
    - "--disable-pyroscope"
    - "--disable-rendering"
    - "--disable-annotations"
    - "--disable-proxied"
    - "--disable-examples"
    - "--disable-runpanelquery"

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi

podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000

containerSecurityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  capabilities:
    drop:
      - ALL

probes:
  liveness:
    enabled: true
    path: /healthz
    initialDelaySeconds: 30
    periodSeconds: 20
    timeoutSeconds: 3
    failureThreshold: 3

  readiness:
    enabled: true
    path: /healthz
    initialDelaySeconds: 10
    periodSeconds: 10
    timeoutSeconds: 3
    failureThreshold: 3

  startup:
    enabled: true
    path: /healthz
    initialDelaySeconds: 5
    periodSeconds: 5
    timeoutSeconds: 3
    failureThreshold: 12

nodeSelector: {}

tolerations: []

affinity: {}
EOF
```

### What each block does

```yaml
replicaCount: 1
```

Runs one MCP pod. For first rollout, one replica is simpler and safer.

```yaml
image:
  registry: YOUR_JFROG_REGISTRY
  repository: cso/obseng-keystone-infra/grafana/mcp-grafana
  tag: "0.13.1"
```

Tells Kubernetes to pull the Grafana MCP image from your private JFrog path.

```yaml
pullPolicy: IfNotPresent
```

If the image already exists on the node, Kubernetes will not always pull it again.

```yaml
namespace: np-keystone
```

Deploys MCP into your existing Keystone namespace.

```yaml
grafana:
  url: "http://grafana-service.np-keystone.svc.cluster.local:3000"
```

This points MCP to your Grafana Kubernetes Service. Since your Grafana pod is multi-container, the service is the correct stable endpoint, not the pod name.

```yaml
tokenSecretName: grafana-mcp-token
tokenSecretKey: token
```

Tells the Deployment where to read the Grafana service account token from.

```yaml
serviceAccount:
  automountServiceAccountToken: false
```

Prevents Kubernetes from automatically mounting a Kubernetes API token into the MCP pod. MCP does not need Kubernetes API access.

```yaml
service:
  type: ClusterIP
```

Makes MCP internal-only. No external exposure.

```yaml
mcp:
  args:
```

These are the command-line flags passed to the MCP container.

```yaml
- "-t"
- "streamable-http"
```

Runs MCP using streamable HTTP transport, which is better for an internal Kubernetes service.

```yaml
- "--endpoint-path"
- "/mcp"
```

Makes the MCP endpoint:

```text
http://grafana-mcp.np-keystone.svc.cluster.local:8000/mcp
```

```yaml
- "--disable-write"
```

Runs MCP in read-only mode. Grafana documents this as the flag used to prevent write operations while still allowing reads, queries, and resource listing. ([Grafana Labs][2])

```yaml
- "--disable-admin"
- "--disable-alerting"
- "--disable-incident"
- "--disable-oncall"
```

Disables high-risk or unnecessary tool categories for your first deployment. Grafana MCP supports disabling categories with `--disable-<category>`. ([Grafana Labs][3])

```yaml
- "--disable-proxied"
```

Disables proxied tools. This matters because proxied tools can load additional tools through Grafana datasource proxy; Grafana notes that proxied tools are enabled by default and `--disable-proxied` disables them. ([Grafana Labs][4])

```yaml
resources:
```

Sets CPU and memory requests/limits so the pod does not consume too many resources.

```yaml
podSecurityContext:
containerSecurityContext:
```

Hardens the pod by running it as non-root, disabling privilege escalation, dropping Linux capabilities, and using a read-only root filesystem.

```yaml
probes:
```

Adds liveness, readiness, and startup probes against `/healthz`.

---

## File 3: `grafana-mcp/templates/_helpers.tpl`

```bash
cat > grafana-mcp/templates/_helpers.tpl <<'EOF'
{{- define "grafana-mcp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "grafana-mcp.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- include "grafana-mcp.name" . }}
{{- end }}
{{- end }}

{{- define "grafana-mcp.labels" -}}
app.kubernetes.io/name: {{ include "grafana-mcp.name" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/instance: {{ include "grafana-mcp.fullname" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "grafana-mcp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "grafana-mcp.name" . }}
app.kubernetes.io/instance: {{ include "grafana-mcp.fullname" . }}
{{- end }}
EOF
```

### What each block does

```yaml
grafana-mcp.name
```

Creates the base name for the app.

```yaml
grafana-mcp.fullname
```

Creates the full Kubernetes resource name. In your case, it will normally be:

```text
grafana-mcp
```

```yaml
grafana-mcp.labels
```

Creates shared metadata labels used by the Deployment, Service, and ServiceAccount.

```yaml
grafana-mcp.selectorLabels
```

Creates labels used by the Service to find the MCP pod.

---

## File 4: `grafana-mcp/templates/serviceaccount.yaml`

```bash
cat > grafana-mcp/templates/serviceaccount.yaml <<'EOF'
{{- if .Values.serviceAccount.create -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ .Values.serviceAccount.name | default (include "grafana-mcp.fullname" .) }}
  namespace: {{ .Values.namespace }}
  labels:
    {{- include "grafana-mcp.labels" . | nindent 4 }}
automountServiceAccountToken: {{ .Values.serviceAccount.automountServiceAccountToken }}
{{- end }}
EOF
```

### What each block does

```yaml
apiVersion: v1
kind: ServiceAccount
```

Creates a Kubernetes ServiceAccount.

```yaml
metadata:
  name: grafana-mcp
  namespace: np-keystone
```

Metadata gives Kubernetes the object name and namespace.

```yaml
labels:
```

Adds standard Helm/Kubernetes labels for tracking.

```yaml
automountServiceAccountToken: false
```

Prevents the pod from receiving a Kubernetes API token.

---

## File 5: `grafana-mcp/templates/deployment.yaml`

```bash
cat > grafana-mcp/templates/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "grafana-mcp.fullname" . }}
  namespace: {{ .Values.namespace }}
  labels:
    {{- include "grafana-mcp.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "grafana-mcp.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "grafana-mcp.selectorLabels" . | nindent 8 }}
        {{- with .Values.podLabels }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      annotations:
        {{- with .Values.podAnnotations }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
    spec:
      automountServiceAccountToken: {{ .Values.serviceAccount.automountServiceAccountToken }}
      serviceAccountName: {{ .Values.serviceAccount.name | default (include "grafana-mcp.fullname" .) }}

      securityContext:
        {{- toYaml .Values.podSecurityContext | nindent 8 }}

      containers:
        - name: grafana-mcp
          image: "{{ .Values.image.registry }}/{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}

          args:
            {{- range .Values.mcp.args }}
            - {{ . | quote }}
            {{- end }}

          env:
            - name: GRAFANA_URL
              value: {{ .Values.grafana.url | quote }}

            - name: GRAFANA_SERVICE_ACCOUNT_TOKEN
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.grafana.tokenSecretName }}
                  key: {{ .Values.grafana.tokenSecretKey }}

            - name: TMPDIR
              value: /tmp

          ports:
            - name: http
              containerPort: {{ .Values.service.targetPort }}
              protocol: TCP

          {{- if .Values.probes.liveness.enabled }}
          livenessProbe:
            httpGet:
              path: {{ .Values.probes.liveness.path }}
              port: http
            initialDelaySeconds: {{ .Values.probes.liveness.initialDelaySeconds }}
            periodSeconds: {{ .Values.probes.liveness.periodSeconds }}
            timeoutSeconds: {{ .Values.probes.liveness.timeoutSeconds }}
            failureThreshold: {{ .Values.probes.liveness.failureThreshold }}
          {{- end }}

          {{- if .Values.probes.readiness.enabled }}
          readinessProbe:
            httpGet:
              path: {{ .Values.probes.readiness.path }}
              port: http
            initialDelaySeconds: {{ .Values.probes.readiness.initialDelaySeconds }}
            periodSeconds: {{ .Values.probes.readiness.periodSeconds }}
            timeoutSeconds: {{ .Values.probes.readiness.timeoutSeconds }}
            failureThreshold: {{ .Values.probes.readiness.failureThreshold }}
          {{- end }}

          {{- if .Values.probes.startup.enabled }}
          startupProbe:
            httpGet:
              path: {{ .Values.probes.startup.path }}
              port: http
            initialDelaySeconds: {{ .Values.probes.startup.initialDelaySeconds }}
            periodSeconds: {{ .Values.probes.startup.periodSeconds }}
            timeoutSeconds: {{ .Values.probes.startup.timeoutSeconds }}
            failureThreshold: {{ .Values.probes.startup.failureThreshold }}
          {{- end }}

          resources:
            {{- toYaml .Values.resources | nindent 12 }}

          securityContext:
            {{- toYaml .Values.containerSecurityContext | nindent 12 }}

          volumeMounts:
            - name: tmp
              mountPath: /tmp

      volumes:
        - name: tmp
          emptyDir: {}

      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}

      {{- with .Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}

      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
EOF
```

### What each block does

```yaml
apiVersion: apps/v1
kind: Deployment
```

Creates a Kubernetes Deployment for the MCP server.

```yaml
metadata:
  name:
  namespace:
  labels:
```

Metadata identifies the Deployment and puts it in `np-keystone`.

```yaml
spec:
  replicas: 1
```

Runs one MCP pod.

```yaml
selector:
  matchLabels:
```

Tells the Deployment which pods it owns.

```yaml
template:
  metadata:
    labels:
```

Defines labels applied to the pod. The Service uses these labels to send traffic to this pod.

```yaml
automountServiceAccountToken: false
```

Prevents Kubernetes API credentials from being mounted into the pod.

```yaml
serviceAccountName: grafana-mcp
```

Uses the Kubernetes ServiceAccount created by `serviceaccount.yaml`.

```yaml
securityContext:
```

Applies pod-level security settings.

```yaml
containers:
  - name: grafana-mcp
```

Defines the MCP container.

```yaml
image:
```

Pulls your private JFrog MCP image.

```yaml
args:
```

Starts MCP with the flags from `values.yaml`.

```yaml
env:
  - name: GRAFANA_URL
```

Passes this Grafana URL to MCP:

```text
http://grafana-service.np-keystone.svc.cluster.local:3000
```

```yaml
- name: GRAFANA_SERVICE_ACCOUNT_TOKEN
  valueFrom:
    secretKeyRef:
```

Reads the Grafana token from the Kubernetes Secret named:

```text
grafana-mcp-token
```

```yaml
ports:
  - name: http
    containerPort: 8000
```

Makes the MCP container listen on port `8000`.

```yaml
livenessProbe:
```

Restarts the pod if the MCP server becomes unhealthy.

```yaml
readinessProbe:
```

Prevents Kubernetes from sending traffic to the pod until MCP is ready.

```yaml
startupProbe:
```

Gives the pod time to start before liveness checks begin.

```yaml
resources:
```

Controls CPU and memory.

```yaml
securityContext:
```

Applies container-level hardening.

```yaml
volumeMounts:
  - name: tmp
    mountPath: /tmp
```

Provides a writable `/tmp` directory because the root filesystem is read-only.

```yaml
volumes:
  - name: tmp
    emptyDir: {}
```

Creates temporary pod-local storage for `/tmp`.

---

## File 6: `grafana-mcp/templates/service.yaml`

```bash
cat > grafana-mcp/templates/service.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: {{ include "grafana-mcp.fullname" . }}
  namespace: {{ .Values.namespace }}
  labels:
    {{- include "grafana-mcp.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  selector:
    {{- include "grafana-mcp.selectorLabels" . | nindent 4 }}
  ports:
    - name: http
      port: {{ .Values.service.port }}
      targetPort: http
      protocol: TCP
EOF
```

### What each block does

```yaml
apiVersion: v1
kind: Service
```

Creates a Kubernetes Service.

```yaml
metadata:
  name: grafana-mcp
  namespace: np-keystone
```

Creates the service in the same namespace as your Grafana stack.

```yaml
spec:
  type: ClusterIP
```

Makes the MCP service internal-only.

```yaml
selector:
```

Matches the MCP pod labels.

```yaml
ports:
  - name: http
    port: 8000
    targetPort: http
```

Exposes MCP internally on port `8000`.

The internal MCP URL becomes:

```text
http://grafana-mcp.np-keystone.svc.cluster.local:8000/mcp
```

---

# 5. Separate secret file

Create this outside GitHub, or make sure it is ignored by Git.

```bash
cat > grafana-mcp-secrets.yaml <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: grafana-mcp-token
  namespace: np-keystone
type: Opaque
stringData:
  token: "PASTE_GRAFANA_SERVICE_ACCOUNT_TOKEN_HERE"
EOF
```

Apply it:

```bash
kubectl apply -f grafana-mcp-secrets.yaml
```

Verify it:

```bash
kubectl get secret grafana-mcp-token -n np-keystone
```

### What each block does

```yaml
apiVersion: v1
kind: Secret
```

Creates a Kubernetes Secret.

```yaml
metadata:
  name: grafana-mcp-token
  namespace: np-keystone
```

Names the secret and stores it in the same namespace where MCP runs.

```yaml
type: Opaque
```

Generic Kubernetes secret type.

```yaml
stringData:
  token:
```

Stores the Grafana service account token as plain text during apply. Kubernetes converts it to base64 internally.

Do not commit this file with the real token.

---

# 6. Add secret file to `.gitignore`

```bash
cat >> .gitignore <<'EOF'

# Local Kubernetes secret for Grafana MCP - do not commit
grafana-mcp-secrets.yaml
EOF
```

---

# 7. Validate before pushing

Run:

```bash
helm lint grafana-mcp
```

Render the chart:

```bash
helm template grafana-mcp grafana-mcp -n np-keystone
```

Confirm the Grafana URL is correct:

```bash
helm template grafana-mcp grafana-mcp -n np-keystone | grep -i "GRAFANA_URL" -A2
```

Confirm there is no JFrog pull secret:

```bash
helm template grafana-mcp grafana-mcp -n np-keystone | grep -i "imagePullSecrets" || echo "No imagePullSecrets found"
```

Confirm there is no NetworkPolicy:

```bash
helm template grafana-mcp grafana-mcp -n np-keystone | grep -i "NetworkPolicy" || echo "No NetworkPolicy found"
```

---

# 8. Commit safe files only

```bash
git status
git add grafana-mcp
git add .gitignore
git commit -m "Add Grafana MCP internal read-only deployment"
git push origin develop
```

Do not commit:

```text
grafana-mcp-secrets.yaml
```

---

# 9. After ArgoCD syncs, test MCP

Check the pod:

```bash
kubectl get pods -n np-keystone | grep -i grafana-mcp
```

Check the service:

```bash
kubectl get svc -n np-keystone | grep -i grafana-mcp
```

Check MCP logs:

```bash
kubectl logs -n np-keystone deployment/grafana-mcp --tail=100
```

Health check from inside the cluster:

```bash
kubectl run mcp-health-test \
  -n np-keystone \
  --rm -it \
  --image=curlimages/curl \
  --restart=Never \
  -- curl -i http://grafana-mcp.np-keystone.svc.cluster.local:8000/healthz
```

Expected:

```text
HTTP/1.1 200 OK
```

Port-forward for local testing:

```bash
kubectl port-forward -n np-keystone svc/grafana-mcp 8000:8000
```

Then test:

```bash
curl -i http://localhost:8000/healthz
```

Your local MCP endpoint is:

```text
http://localhost:8000/mcp
```

Your in-cluster MCP endpoint is:

```text
http://grafana-mcp.np-keystone.svc.cluster.local:8000/mcp
```

[1]: https://grafana.com/docs/grafana/latest/developer-resources/mcp/configure/authentication/ "Authentication | Grafana documentation
"
[2]: https://grafana.com/docs/grafana/latest/developer-resources/mcp/configure/enable-and-disable-tools/?utm_source=chatgpt.com "Enable and disable tools | Grafana documentation"
[3]: https://grafana.com/docs/grafana/latest/developer-resources/mcp/configure/command-line-flags/?utm_source=chatgpt.com "Command-line flags | Grafana documentation"
[4]: https://grafana.com/docs/grafana/latest/developer-resources/mcp/configure/proxied-tools/?utm_source=chatgpt.com "Proxied tools | Grafana documentation"
