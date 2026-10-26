{{- define "accounts-api.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "accounts-api.fullname" -}}
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

{{- define "accounts-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "accounts-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "accounts-api.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{ include "accounts-api.selectorLabels" . }}
app.kubernetes.io/version: {{ include "accounts-api.imageTag" . | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "accounts-api.imageTag" -}}
{{- default .Chart.AppVersion .Values.image.tag | trunc 63 }}
{{- end }}

{{- define "accounts-api.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "accounts-api.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "accounts-api.authSecretName" -}}
{{- default (printf "%s-auth" (include "accounts-api.fullname" .)) .Values.auth.existingSecret }}
{{- end }}
