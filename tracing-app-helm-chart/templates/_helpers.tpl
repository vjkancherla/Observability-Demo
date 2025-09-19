{{/*
Expand the name of the chart.
*/}}
{{- define "tracing-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "tracing-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "tracing-app.labels" -}}
helm.sh/chart: {{ include "tracing-app.chart" . }}
app.kubernetes.io/name: {{ include "tracing-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "tracing-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tracing-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}