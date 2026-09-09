{{/*
Expand the name of the chart.
Uses Release.Name so each service gets a unique app.kubernetes.io/name label
when the same chart is installed once per service.
*/}}
{{- define "mts-ijp.name" -}}
{{- if .Values.nameOverride -}}
{{- .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
Truncated at 63 chars because some Kubernetes name fields are limited by the DNS spec.
*/}}
{{- define "mts-ijp.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else if .Values.nameOverride -}}
{{- .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "mts-ijp.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "mts-ijp.labels" -}}
helm.sh/chart: {{ include "mts-ijp.chart" . }}
{{ include "mts-ijp.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: mts-ijp
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Selector labels. Immutable across upgrades — spec.selector cannot be patched.
*/}}
{{- define "mts-ijp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mts-ijp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Return the target Namespace for all resources.
*/}}
{{- define "mts-ijp.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Full container image reference.
Single field format: "registry/repository:tag@sha256:digest"
*/}}
{{- define "mts-ijp.image" -}}
{{- required "image.name is required" .Values.image.name -}}
{{- end -}}

{{/*
Return image pull secrets.
Priority: image.pullSecrets > global.imagePullSecrets
*/}}
{{- define "mts-ijp.imagePullSecrets" -}}
{{- $pullSecrets := list -}}
{{- if .Values.global -}}
{{- range .Values.global.imagePullSecrets -}}
{{- $pullSecrets = append $pullSecrets . -}}
{{- end -}}
{{- end -}}
{{- range .Values.image.pullSecrets -}}
{{- $pullSecrets = append $pullSecrets . -}}
{{- end -}}
{{- if not (empty $pullSecrets) -}}
imagePullSecrets:
{{- range $pullSecrets }}
  - name: {{ .name }}
{{- end }}
{{- end -}}
{{- end -}}

{{/*
Secret name for envFromSecret.
*/}}
{{- define "mts-ijp.secretName" -}}
{{- required "envFromSecret.secretName is required when envFromSecret.enabled" .Values.envFromSecret.secretName -}}
{{- end -}}

{{/*
PersistentVolumeClaim name.
*/}}
{{- define "mts-ijp.pvcName" -}}
{{- if .Values.persistence.existingClaim -}}
{{- .Values.persistence.existingClaim -}}
{{- else -}}
{{- printf "%s-data" (include "mts-ijp.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
PersistentVolume name (static provisioning).
*/}}
{{- define "mts-ijp.pvName" -}}
{{- default (printf "%s-%s-pv" (include "mts-ijp.namespace" .) (include "mts-ijp.fullname" .)) .Values.persistence.volume.name -}}
{{- end -}}

{{/*
Render storageClassName per the standard convention:
  ""  -> omit the field entirely (use the cluster default StorageClass)
  "-" -> storageClassName: "" (no class; required to bind a static PV)
  any -> that class name
*/}}
{{- define "mts-ijp.storageClass" -}}
{{- if .Values.persistence.storageClass -}}
{{- if eq .Values.persistence.storageClass "-" -}}
storageClassName: ""
{{- else -}}
storageClassName: {{ .Values.persistence.storageClass | quote }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Return the appropriate apiVersion for PodDisruptionBudget.
*/}}
{{- define "mts-ijp.pdb.apiVersion" -}}
{{- if .Capabilities.APIVersions.Has "policy/v1" -}}
policy/v1
{{- else -}}
policy/v1beta1
{{- end -}}
{{- end -}}
