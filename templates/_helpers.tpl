{{/*
Chart name truncated to 63 characters.
*/}}
{{- define "artemis-edge.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name truncated to 63 characters.
*/}}
{{- define "artemis-edge.fullname" -}}
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
Common labels applied to all resources.
*/}}
{{- define "artemis-edge.labels" -}}
helm.sh/chart: {{ include "artemis-edge.name" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: artemis-edge-acm-demo
demo.redhat.com/application: "artemis-edge-acm"
{{- end }}

{{/*
RHDP userinfo label for data passback.
*/}}
{{- define "artemis-edge.userinfoLabel" -}}
demo.redhat.com/userinfo: ""
{{- end }}

{{/*
Broker properties: common security roles for messages.# address.
*/}}
{{- define "artemis-edge.brokerSecurityRoles" -}}
securityRoles."messages.#".admin.createAddress=true
securityRoles."messages.#".admin.deleteAddress=true
securityRoles."messages.#".admin.send=true
securityRoles."messages.#".admin.consume=true
securityRoles."messages.#".admin.browse=true
securityRoles."messages.#".admin.createDurableQueue=true
securityRoles."messages.#".admin.deleteDurableQueue=true
securityRoles."messages.#".admin.createNonDurableQueue=true
securityRoles."messages.#".admin.deleteNonDurableQueue=true
securityRoles."messages.#".admin.manage=true
securityRoles."messages.#".producer.createAddress=true
securityRoles."messages.#".producer.send=true
{{- end }}

{{/*
Broker properties: common address settings for messages.# address.
*/}}
{{- define "artemis-edge.brokerAddressSettings" -}}
addressSettings."messages.#".autoDeleteAddresses=true
addressSettings."messages.#".autoDeleteAddressesDelay=0
addressSettings."messages.#".autoDeleteQueues=true
addressSettings."messages.#".autoDeleteCreatedQueues=true
addressSettings."messages.#".autoDeleteQueuesDelay=0
addressSettings."messages.#".autoDeleteQueuesMessageCount=1000
addressSettings."messages.#".defaultPurgeOnNoConsumers=true
{{- end }}

{{/*
Broker acceptor list (parameterized by TLS secret name).
When tls.enabled is false, only plain-text acceptors are created.
Call with: include "artemis-edge.brokerAcceptorsWithSecret" (dict "Values" .Values "tlsSecretName" "broker-tls-secret")
*/}}
{{- define "artemis-edge.brokerAcceptorsWithSecret" -}}
- name: core-acceptor
  protocols: core
  port: 61616
{{- if .Values.tls.enabled }}
- name: cores-acceptor
  protocols: core
  port: 61617
  sslEnabled: true
  sslSecret: {{ .tlsSecretName }}
  needClientAuth: false
  expose: true
{{- end }}
- name: amqp-acceptor
  protocols: amqp
  port: 5672
{{- if .Values.tls.enabled }}
- name: amqps-acceptor
  protocols: amqp
  port: 5671
  sslEnabled: true
  sslSecret: {{ .tlsSecretName }}
  needClientAuth: false
  expose: true
{{- end }}
- name: mqtt-acceptor
  protocols: mqtt
  port: 1833
{{- if .Values.tls.enabled }}
- name: mqtts-acceptor
  protocols: mqtt
  port: 8883
  sslEnabled: true
  sslSecret: {{ .tlsSecretName }}
  needClientAuth: false
  expose: true
{{- end }}
{{- end }}

{{/*
Backward-compatible wrapper: hub brokers use the shared "broker-tls-secret".
*/}}
{{- define "artemis-edge.brokerAcceptors" -}}
{{- include "artemis-edge.brokerAcceptorsWithSecret" (dict "Values" .Values "tlsSecretName" "broker-tls-secret") -}}
{{- end }}
