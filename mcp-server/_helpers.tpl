{{/*
Expand the name of the chart.
*/}}
{{- define "grafana-mcp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
Truncate at 63 chars because some Kubernetes name fields are limited to this.
*/}}
{{- define "grafana-mcp.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart label value.
*/}}
{{- define "grafana-mcp.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels — applied to every resource.
*/}}
{{- define "grafana-mcp.labels" -}}
helm.sh/chart: {{ include "grafana-mcp.chart" . }}
app.kubernetes.io/name: {{ include "grafana-mcp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: mcp-server
environment: {{ .Values.environment }}
{{- end }}

{{/*
Selector labels — used in matchLabels (must be stable, never change after first deploy).
*/}}
{{- define "grafana-mcp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "grafana-mcp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Full image reference — registry/repository:tag
*/}}
{{- define "grafana-mcp.image" -}}
{{- printf "%s/%s:%s" .Values.image.registry .Values.image.repository .Values.image.tag }}
{{- end }}

{{/*
ServiceAccount name.
*/}}
{{- define "grafana-mcp.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "grafana-mcp.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Build the args list for the MCP server container.
Starts with transport, adds --metrics if enabled, --disable-write if set,
then appends any entries from disabledTools.
*/}}
{{- define "grafana-mcp.args" -}}
- "-t"
- {{ .Values.mcp.transport | quote }}
{{- if .Values.mcp.metrics }}
- "--metrics"
{{- end }}
{{- if .Values.mcp.disableWrite }}
- "--disable-write"
{{- end }}
{{- range .Values.mcp.disabledTools }}
- {{ printf "--disable-%s" . | quote }}
{{- end }}
{{- end }}
