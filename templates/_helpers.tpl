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

{{/*
SNO edge brokerProperties: address federation to hub-01 AMQPS Route (KCS 7104022/7042028).
Call with: include "artemis-edge.snoFederationBrokerProperties" (dict "spoke" . "Values" $.Values)
*/}}
{{- define "artemis-edge.snoFederationBrokerProperties" -}}
{{- $spoke := .spoke -}}
{{- $v := .Values -}}
{{- $hub := (index $v.hubBrokers 0).name -}}
{{- $uri := printf "tcp://%s-broker-amqps-acceptor-0-svc-rte-%s.%s:443?sslEnabled=true&trustAll=true&verifyHost=false&useTopologyForLoadBalancing=false" $hub $v.global.namespace $v.global.clusterDomain -}}
- {{ printf "acceptorConfigurations.amqps-acceptor.params.sslAutoReload=true" | quote }}
- {{ printf "AMQPConnections.%s-connection.autostart=true" $hub | quote }}
- {{ printf "AMQPConnections.%s-connection.uri=%s" $hub $uri | quote }}
- {{ printf "AMQPConnections.%s-connection.user=%s" $hub $v.edgeBrokerDefaults.adminUser | quote }}
- {{ printf "AMQPConnections.%s-connection.password=%s" $hub $v.edgeBrokerDefaults.adminPassword | quote }}
- {{ printf "AMQPConnections.%s-connection.retryInterval=5000" $hub | quote }}
- {{ printf "AMQPConnections.%s-connection.reconnectAttempts=-1" $hub | quote }}
- {{ printf "AMQPConnections.%s-connection.federations.%s-federation.type=FEDERATION" $hub $spoke.name | quote }}
- {{ printf "AMQPConnections.%s-connection.federations.%s-federation.localAddressPolicies.local-policy.autoDelete=true" $hub $spoke.name | quote }}
- {{ printf "AMQPConnections.%s-connection.federations.%s-federation.localAddressPolicies.local-policy.autoDeleteDelay=0" $hub $spoke.name | quote }}
- {{ printf "AMQPConnections.%s-connection.federations.%s-federation.localAddressPolicies.local-policy.autoDeleteMessageCount=1000" $hub $spoke.name | quote }}
- {{ printf "AMQPConnections.%s-connection.federations.%s-federation.localAddressPolicies.local-policy.includes.all.addressMatch=messages.ALL.#" $hub $spoke.name | quote }}
- {{ printf "AMQPConnections.%s-connection.federations.%s-federation.remoteAddressPolicies.remote-policy.autoDelete=true" $hub $spoke.name | quote }}
- {{ printf "AMQPConnections.%s-connection.federations.%s-federation.remoteAddressPolicies.remote-policy.autoDeleteDelay=0" $hub $spoke.name | quote }}
- {{ printf "AMQPConnections.%s-connection.federations.%s-federation.remoteAddressPolicies.remote-policy.autoDeleteMessageCount=1000" $hub $spoke.name | quote }}
- {{ printf "AMQPConnections.%s-connection.federations.%s-federation.remoteAddressPolicies.remote-policy.includes.region.addressMatch=messages.%s.#" $hub $spoke.name $spoke.region | quote }}
{{- end }}

{{/*
RoleBinding/ClusterRoleBinding subjects for workshop users.
*/ -}}
{{- define "artemis-edge.workshopUserSubjects" -}}
{{- $users := list "user1" "user2" }}
{{- if and .Values.workshop .Values.workshop.users }}
{{- $users = .Values.workshop.users }}
{{- end }}
{{- range $users -}}
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: {{ . }}
{{ end -}}
{{- end }}
