Based on your screenshot, **do not reuse `jfrog-build-push.yaml` exactly as-is** for Grafana MCP. That workflow is built around a local `Dockerfile`. For Grafana MCP, you should **mirror the official image into JFrog**, then deploy your own internal Helm chart from the repo.

Grafana MCP connects to Grafana using `GRAFANA_URL` and `GRAFANA_SERVICE_ACCOUNT_TOKEN`; it gives access to Grafana and its ecosystem based on that token’s permissions. ([GitHub][1])

Use this structure:

```text
obseng-keystone-infra/
├── .github/
│   └── workflows/
│       └── grafana-mcp-jfrog-mirror.yaml
├── grafana-mcp/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── _helpers.tpl
│       ├── serviceaccount.yaml
│       ├── deployment.yaml
│       ├── service.yaml
│       └── networkpolicy.yaml
└── grafana-mcp-secrets.yaml   # local only, do not commit
```

---

## 1. Create the Grafana MCP folder

From the root of your repo:

```bash
mkdir -p grafana-mcp/templates
```

---

## 2. Add GitHub Action to mirror the image to JFrog

Create this file:

```bash
cat > .github/workflows/grafana-mcp-jfrog-mirror.yaml <<'EOF'
name: Mirror Grafana MCP Image To JFrog

on:
  push:
    branches:
      - develop
    paths:
      - ".github/workflows/grafana-mcp-jfrog-mirror.yaml"
      - "grafana-mcp/**"

  workflow_dispatch:
    inputs:
      mcp_version:
        description: "Grafana MCP image version to mirror"
        required: true
        default: "0.13.1"
      environment_tag:
        description: "Optional mutable environment tag"
        required: true
        default: "non-prod"
        type: choice
        options:
          - dev
          - non-prod
          - prod
          - none

permissions:
  contents: write

env:
  SOURCE_IMAGE: docker.io/grafana/mcp-grafana
  IMAGE_NAME: mcp-grafana

  # Match your internal JFrog folder convention.
  # Change this if your JFrog repo path is different.
  JFROG_REPO_PATH: cso/obseng-keystone-infra/grafana/mcp-grafana

jobs:
  mirror-grafana-mcp:
    runs-on: sw-ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set image metadata
        id: meta
        run: |
          VERSION="${{ github.event.inputs.mcp_version }}"
          ENV_TAG="${{ github.event.inputs.environment_tag }}"

          if [ -z "$VERSION" ]; then
            VERSION="0.13.1"
          fi

          if [ -z "$ENV_TAG" ]; then
            ENV_TAG="non-prod"
          fi

          DEST_IMAGE="${{ secrets.ARTIFACTORY_REGISTRY }}/${JFROG_REPO_PATH}"

          echo "VERSION=$VERSION" >> "$GITHUB_OUTPUT"
          echo "ENV_TAG=$ENV_TAG" >> "$GITHUB_OUTPUT"
          echo "DEST_IMAGE=$DEST_IMAGE" >> "$GITHUB_OUTPUT"

          echo "Source image: ${SOURCE_IMAGE}:${VERSION}"
          echo "Destination image: ${DEST_IMAGE}:${VERSION}"
          echo "Environment tag: ${ENV_TAG}"

      - name: Log in to JFrog Docker Registry
        run: |
          echo "${{ secrets.ARTIFACTORY_API_KEY }}" | docker login "${{ secrets.ARTIFACTORY_REGISTRY }}" \
            --username "${{ secrets.ARTIFACTORY_USERNAME }}" \
            --password-stdin

      - name: Pull official Grafana MCP image
        run: |
          docker pull "${SOURCE_IMAGE}:${{ steps.meta.outputs.VERSION }}"

      - name: Tag image for JFrog
        run: |
          docker tag "${SOURCE_IMAGE}:${{ steps.meta.outputs.VERSION }}" \
            "${{ steps.meta.outputs.DEST_IMAGE }}:${{ steps.meta.outputs.VERSION }}"

          if [ "${{ steps.meta.outputs.ENV_TAG }}" != "none" ]; then
            docker tag "${SOURCE_IMAGE}:${{ steps.meta.outputs.VERSION }}" \
              "${{ steps.meta.outputs.DEST_IMAGE }}:${{ steps.meta.outputs.ENV_TAG }}"
          fi

      - name: Push immutable version tag to JFrog
        run: |
          docker push "${{ steps.meta.outputs.DEST_IMAGE }}:${{ steps.meta.outputs.VERSION }}"

      - name: Push environment tag to JFrog
        if: ${{ steps.meta.outputs.ENV_TAG != 'none' }}
        run: |
          docker push "${{ steps.meta.outputs.DEST_IMAGE }}:${{ steps.meta.outputs.ENV_TAG }}"

      - name: Write or update images.csv
        run: |
          CSV_FILE="images.csv"
          IMAGE_NAME="grafana-mcp"
          VERSION="${{ steps.meta.outputs.VERSION }}"
          ENV_TAG="${{ steps.meta.outputs.ENV_TAG }}"
          DEST_IMAGE="${{ steps.meta.outputs.DEST_IMAGE }}"
          LABELS="source=docker.io/grafana/mcp-grafana;component=grafana-mcp;namespace=np-keystone"

          if [ ! -f "$CSV_FILE" ]; then
            echo "Image Name,Tag,Location,Labels" > "$CSV_FILE"
          fi

          VERSION_ROW="$IMAGE_NAME,$VERSION,$DEST_IMAGE:$VERSION,$LABELS"

          if ! grep -q "$IMAGE_NAME,$VERSION,$DEST_IMAGE:$VERSION" "$CSV_FILE"; then
            echo "$VERSION_ROW" >> "$CSV_FILE"
          fi

          if [ "$ENV_TAG" != "none" ]; then
            ENV_ROW="$IMAGE_NAME,$ENV_TAG,$DEST_IMAGE:$ENV_TAG,$LABELS"
            if ! grep -q "$IMAGE_NAME,$ENV_TAG,$DEST_IMAGE:$ENV_TAG" "$CSV_FILE"; then
              echo "$ENV_ROW" >> "$CSV_FILE"
            fi
          fi

      - name: Commit and push images.csv
        run: |
          git config --global user.email "github-actions[bot]@users.noreply.github.com"
          git config --global user.name "github-actions[bot]"

          git add images.csv

          if git diff --cached --quiet; then
            echo "No changes to images.csv"
            exit 0
          fi

          git commit -m "Update images.csv with Grafana MCP image metadata"

          git pull origin "${{ github.ref_name }}" --rebase || echo "No upstream changes"
          git push origin "HEAD:${{ github.ref_name }}"
EOF
```

This workflow uses the same secrets your screenshot already shows:

```text
ARTIFACTORY_REGISTRY
ARTIFACTORY_USERNAME
ARTIFACTORY_API_KEY
```

Make sure `ARTIFACTORY_REGISTRY` is only the registry host, for example:

```text
jfrog.company.com
```

Not:

```text
https://jfrog.company.com
```

---

## 3. Create the Helm chart

### `grafana-mcp/Chart.yaml`

```bash
cat > grafana-mcp/Chart.yaml <<'EOF'
apiVersion: v2
name: grafana-mcp
description: Internal Helm chart for Grafana MCP Server in the Keystone observability platform
type: application
version: 0.1.0
appVersion: "0.13.1"
EOF
```

---

### `grafana-mcp/values.yaml`

Replace these two values:

```text
YOUR_JFROG_REGISTRY
cso/obseng-keystone-infra/grafana/mcp-grafana
```

Also replace the Grafana service name if yours is not `np-grafana`.

Get your Grafana service name:

```bash
kubectl get svc -n np-keystone | grep -i grafana
```

Create the values file:

```bash
cat > grafana-mcp/values.yaml <<'EOF'
replicaCount: 1

image:
  registry: YOUR_JFROG_REGISTRY
  repository: cso/obseng-keystone-infra/grafana/mcp-grafana
  tag: "0.13.1"
  pullPolicy: IfNotPresent

imagePullSecrets:
  - name: jfrog-docker-pull

nameOverride: ""
fullnameOverride: ""

namespace: np-keystone

grafana:
  url: "http://np-grafana.np-keystone.svc.cluster.local:3000"
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
    - "--disable-write"
    - "--disable-admin"
    - "--disable-incident"
    - "--disable-oncall"
    - "--disable-alerting"
    - "--disable-sift"
    - "--disable-pyroscope"
    - "--disable-rendering"
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

networkPolicy:
  enabled: true

  # Only pods with this label can call the MCP service.
  allowedClientPodLabel:
    grafana-mcp-client: "true"

  # Confirm this label matches your Grafana StatefulSet pods.
  grafanaPodLabel:
    app.kubernetes.io/name: grafana

nodeSelector: {}

tolerations: []

affinity: {}
EOF
```

Grafana MCP supports `streamable-http`, `--address`, and `--endpoint-path`; the `/healthz` endpoint is available for SSE and streamable HTTP mode. ([GitHub][1]) ([GitHub][1])

The `--disable-write` flag is important because it blocks create/update operations while still allowing read operations like dashboard reads, PromQL/LogQL queries, and resource listing. ([GitHub][1])

---

## 4. Add Helm templates

### `grafana-mcp/templates/_helpers.tpl`

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

---

### `grafana-mcp/templates/serviceaccount.yaml`

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

---

### `grafana-mcp/templates/deployment.yaml`

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

      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}

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

---

### `grafana-mcp/templates/service.yaml`

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

---

### `grafana-mcp/templates/networkpolicy.yaml`

```bash
cat > grafana-mcp/templates/networkpolicy.yaml <<'EOF'
{{- if .Values.networkPolicy.enabled }}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "grafana-mcp.fullname" . }}-restrict
  namespace: {{ .Values.namespace }}
  labels:
    {{- include "grafana-mcp.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "grafana-mcp.selectorLabels" . | nindent 6 }}

  policyTypes:
    - Ingress
    - Egress

  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: {{ .Values.namespace }}
          podSelector:
            matchLabels:
              {{- toYaml .Values.networkPolicy.allowedClientPodLabel | nindent 14 }}
      ports:
        - protocol: TCP
          port: {{ .Values.service.targetPort }}

  egress:
    # DNS
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53

    # Grafana
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: {{ .Values.namespace }}
          podSelector:
            matchLabels:
              {{- toYaml .Values.networkPolicy.grafanaPodLabel | nindent 14 }}
      ports:
        - protocol: TCP
          port: 3000
{{- end }}
EOF
```

---

## 5. Create the separate secret file

Create this **outside GitHub** or add it to `.gitignore`.

```bash
cat >> .gitignore <<'EOF'

# Local Kubernetes secrets - do not commit
grafana-mcp-secrets.yaml
EOF
```

Now create the file:

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

---
apiVersion: v1
kind: Secret
metadata:
  name: jfrog-docker-pull
  namespace: np-keystone
type: kubernetes.io/dockerconfigjson
stringData:
  .dockerconfigjson: |
    {
      "auths": {
        "YOUR_JFROG_REGISTRY": {
          "username": "YOUR_JFROG_USERNAME",
          "password": "YOUR_JFROG_ACCESS_TOKEN",
          "auth": "BASE64_OF_USERNAME_COLON_ACCESS_TOKEN"
        }
      }
    }
EOF
```

Generate the `auth` value:

```bash
printf '%s' 'YOUR_JFROG_USERNAME:YOUR_JFROG_ACCESS_TOKEN' | base64
```

Then edit `grafana-mcp-secrets.yaml` and replace:

```text
PASTE_GRAFANA_SERVICE_ACCOUNT_TOKEN_HERE
YOUR_JFROG_REGISTRY
YOUR_JFROG_USERNAME
YOUR_JFROG_ACCESS_TOKEN
BASE64_OF_USERNAME_COLON_ACCESS_TOKEN
```

Apply it:

```bash
kubectl apply -f grafana-mcp-secrets.yaml
```

Verify:

```bash
kubectl get secret grafana-mcp-token -n np-keystone
kubectl get secret jfrog-docker-pull -n np-keystone
```

---

## 6. Validate the Helm chart locally before pushing

```bash
helm lint grafana-mcp
```

Render it:

```bash
helm template grafana-mcp grafana-mcp -n np-keystone
```

Confirm image:

```bash
helm template grafana-mcp grafana-mcp -n np-keystone | grep -i "image:"
```

You should see something like:

```text
image: "YOUR_JFROG_REGISTRY/cso/obseng-keystone-infra/grafana/mcp-grafana:0.13.1"
```

---

## 7. Commit only the safe files

Do **not** commit `grafana-mcp-secrets.yaml`.

```bash
git status
git add .github/workflows/grafana-mcp-jfrog-mirror.yaml
git add grafana-mcp
git add .gitignore
git commit -m "Add Grafana MCP Helm deployment"
git push origin develop
```

The GitHub Action should then mirror:

```text
docker.io/grafana/mcp-grafana:0.13.1
```

to:

```text
YOUR_JFROG_REGISTRY/cso/obseng-keystone-infra/grafana/mcp-grafana:0.13.1
```

---

## 8. After ArgoCD deploys, test it

Check pods:

```bash
kubectl get pods -n np-keystone | grep -i grafana-mcp
```

Check rollout:

```bash
kubectl rollout status deployment/grafana-mcp -n np-keystone
```

Check logs:

```bash
kubectl logs -n np-keystone deployment/grafana-mcp --tail=100
```

Because the NetworkPolicy only allows pods labeled `grafana-mcp-client=true`, run your curl test like this:

```bash
kubectl run mcp-health-test \
  -n np-keystone \
  --rm -it \
  --image=curlimages/curl \
  --labels="grafana-mcp-client=true" \
  --restart=Never \
  -- curl -i http://grafana-mcp.np-keystone.svc.cluster.local:8000/healthz
```

Expected:

```text
HTTP/1.1 200 OK

ok
```

Port-forward test:

```bash
kubectl port-forward -n np-keystone svc/grafana-mcp 8000:8000
```

Then:

```bash
curl -i http://localhost:8000/healthz
```

MCP client URL:

```text
http://localhost:8000/mcp
```

---

## One thing to verify before enabling NetworkPolicy

Check your Grafana pod labels:

```bash
kubectl get pods -n np-keystone --show-labels | grep -i grafana
```

If your Grafana StatefulSet does **not** use this label:

```yaml
app.kubernetes.io/name: grafana
```

update this part in `grafana-mcp/values.yaml`:

```yaml
networkPolicy:
  grafanaPodLabel:
    app.kubernetes.io/name: grafana
```

Use the real label from your Grafana pod.

[1]: https://github.com/grafana/mcp-grafana "GitHub - grafana/mcp-grafana: MCP server for Grafana · GitHub"
