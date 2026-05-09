{{/*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  grafana-mcp — Template Helpers
  All named templates defined here are available to every
  template file in this chart via {{ include "..." . }}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
*/}}

{{/*
────────────────────────────────────────────────────────────
  grafana-mcp.name
────────────────────────────────────────────────────────────
*/}}
{{- define "grafana-mcp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}


{{/*
────────────────────────────────────────────────────────────
  grafana-mcp.fullname
────────────────────────────────────────────────────────────
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
────────────────────────────────────────────────────────────
  grafana-mcp.chart
────────────────────────────────────────────────────────────
*/}}
{{- define "grafana-mcp.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}


{{/*
────────────────────────────────────────────────────────────
  grafana-mcp.labels
────────────────────────────────────────────────────────────
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
────────────────────────────────────────────────────────────
  grafana-mcp.selectorLabels
────────────────────────────────────────────────────────────
*/}}
{{- define "grafana-mcp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "grafana-mcp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}


{{/*
────────────────────────────────────────────────────────────
  grafana-mcp.image
────────────────────────────────────────────────────────────
*/}}
{{- define "grafana-mcp.image" -}}
{{- printf "%s/%s:%s" .Values.image.registry .Values.image.repository .Values.image.tag }}
{{- end }}


{{/*
────────────────────────────────────────────────────────────
  grafana-mcp.serviceAccountName
────────────────────────────────────────────────────────────
*/}}
{{- define "grafana-mcp.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "grafana-mcp.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}


{{/*
────────────────────────────────────────────────────────────
  grafana-mcp.secretName
────────────────────────────────────────────────────────────
*/}}
{{- define "grafana-mcp.secretName" -}}
{{- if .Values.secret.create }}
{{- printf "%s-token" (include "grafana-mcp.fullname" .) }}
{{- else }}
{{- .Values.grafana.tokenSecret | required "grafana.tokenSecret must be set when secret.create is false" }}
{{- end }}
{{- end }}


{{/*
────────────────────────────────────────────────────────────
  grafana-mcp.args
────────────────────────────────────────────────────────────
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