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
SNO edge brokerProperties: AMQP federation to each hubBrokers entry.
Call with: include "artemis-edge.snoFederationBrokerProperties" (dict "spoke" . "Values" $.Values)
*/}}
{{- define "artemis-edge.snoFederationBrokerProperties" -}}
{{- $spoke := .spoke -}}
{{- $v := .Values -}}
{{- /* Global broker settings */ -}}
{{- printf "- %s\n" ("globalMaxSize=1GiB" | quote) -}}
{{- printf "- %s\n" ("clusterConfigurations.my-cluster.messageLoadBalancingType=OFF" | quote) -}}
{{- /* Security roles: messages.# (all) */ -}}
{{- printf "- %s\n" ("securityRoles.\"messages.#\".admin.createAddress=true" | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.#\".admin.deleteAddress=true" | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.#\".admin.send=true" | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.#\".admin.consume=true" | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.#\".admin.browse=true" | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.#\".admin.createDurableQueue=true" | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.#\".admin.deleteDurableQueue=true" | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.#\".admin.createNonDurableQueue=true" | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.#\".admin.deleteNonDurableQueue=true" | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.#\".admin.manage=true" | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.#\".producer.createAddress=true" | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.#\".producer.send=true" | quote) -}}
{{- /* Security roles: messages.REGION.# (own region) — admin */ -}}
{{- printf "- %s\n" (printf "securityRoles.\"messages.%s.#\".admin.createAddress=true" $spoke.region | quote) -}}
{{- printf "- %s\n" (printf "securityRoles.\"messages.%s.#\".admin.deleteAddress=true" $spoke.region | quote) -}}
{{- printf "- %s\n" (printf "securityRoles.\"messages.%s.#\".admin.send=true" $spoke.region | quote) -}}
{{- printf "- %s\n" (printf "securityRoles.\"messages.%s.#\".admin.consume=true" $spoke.region | quote) -}}
{{- printf "- %s\n" (printf "securityRoles.\"messages.%s.#\".admin.browse=true" $spoke.region | quote) -}}
{{- printf "- %s\n" (printf "securityRoles.\"messages.%s.#\".admin.createDurableQueue=true" $spoke.region | quote) -}}
{{- printf "- %s\n" (printf "securityRoles.\"messages.%s.#\".admin.deleteDurableQueue=true" $spoke.region | quote) -}}
{{- printf "- %s\n" (printf "securityRoles.\"messages.%s.#\".admin.createNonDurableQueue=true" $spoke.region | quote) -}}
{{- printf "- %s\n" (printf "securityRoles.\"messages.%s.#\".admin.deleteNonDurableQueue=true" $spoke.region | quote) -}}
{{- printf "- %s\n" (printf "securityRoles.\"messages.%s.#\".admin.manage=true" $spoke.region | quote) -}}
{{- /* Security roles: messages.ALL.# — admin */ -}}
{{- printf "- %s\n" ("securityRoles.\"messages.ALL.#\".admin.createAddress=true" | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.ALL.#\".admin.deleteAddress=true" | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.ALL.#\".admin.send=true" | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.ALL.#\".admin.consume=true" | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.ALL.#\".admin.browse=true" | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.ALL.#\".admin.createDurableQueue=true" | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.ALL.#\".admin.deleteDurableQueue=true" | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.ALL.#\".admin.createNonDurableQueue=true" | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.ALL.#\".admin.deleteNonDurableQueue=true" | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.ALL.#\".admin.manage=true" | quote) -}}
{{- /* Producer/consumer roles for region + ALL */ -}}
{{- printf "- %s\n" (printf "securityRoles.\"messages.%s.#\".producer.createAddress=true" $spoke.region | quote) -}}
{{- printf "- %s\n" (printf "securityRoles.\"messages.%s.#\".producer.send=true" $spoke.region | quote) -}}
{{- printf "- %s\n" (printf "securityRoles.\"messages.%s.#\".consumer.createAddress=true" $spoke.region | quote) -}}
{{- printf "- %s\n" (printf "securityRoles.\"messages.%s.#\".consumer.createDurableQueue=true" $spoke.region | quote) -}}
{{- printf "- %s\n" (printf "securityRoles.\"messages.%s.#\".consumer.createNonDurableQueue=true" $spoke.region | quote) -}}
{{- printf "- %s\n" (printf "securityRoles.\"messages.%s.#\".consumer.deleteNonDurableQueue=true" $spoke.region | quote) -}}
{{- printf "- %s\n" (printf "securityRoles.\"messages.%s.#\".consumer.browse=true" $spoke.region | quote) -}}
{{- printf "- %s\n" (printf "securityRoles.\"messages.%s.#\".consumer.consume=true" $spoke.region | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.ALL.#\".producer.createAddress=true" | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.ALL.#\".producer.send=true" | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.ALL.#\".consumer.createAddress=true" | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.ALL.#\".consumer.createDurableQueue=true" | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.ALL.#\".consumer.createNonDurableQueue=true" | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.ALL.#\".consumer.deleteNonDurableQueue=true" | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.ALL.#\".consumer.browse=true" | quote) -}}
{{- printf "- %s\n" ("securityRoles.\"messages.ALL.#\".consumer.consume=true" | quote) -}}
{{- /* Address settings */ -}}
{{- printf "- %s\n" ("addressSettings.\"messages.#\".autoDeleteAddresses=true" | quote) -}}
{{- printf "- %s\n" ("addressSettings.\"messages.#\".autoDeleteAddressesDelay=0" | quote) -}}
{{- printf "- %s\n" ("addressSettings.\"messages.#\".autoDeleteQueues=true" | quote) -}}
{{- printf "- %s\n" ("addressSettings.\"messages.#\".autoDeleteCreatedQueues=true" | quote) -}}
{{- printf "- %s\n" ("addressSettings.\"messages.#\".autoDeleteQueuesDelay=0" | quote) -}}
{{- printf "- %s\n" ("addressSettings.\"messages.#\".autoDeleteQueuesMessageCount=1000" | quote) -}}
{{- printf "- %s\n" ("addressSettings.\"messages.#\".defaultPurgeOnNoConsumers=true" | quote) -}}
{{- /* AMQP connections to hub brokers */ -}}
{{- range $i, $hubb := $v.hubBrokers -}}
{{- $hub := $hubb.name -}}
{{- $auto := "false" -}}
{{- if eq $i 0 }}{{- $auto = "true" -}}{{- end -}}
{{- $uri := printf "tcp://%s-broker-amqp-acceptor-0-svc.%s.svc.cluster.local:5672" $hub $v.global.namespace -}}
{{- printf "- %s\n" (printf "AMQPConnections.%s-connection.autostart=%s" $hub $auto | quote) -}}
{{- printf "- %s\n" (printf "AMQPConnections.%s-connection.uri=%s" $hub $uri | quote) -}}
{{- printf "- %s\n" (printf "AMQPConnections.%s-connection.user=%s" $hub $v.edgeBrokerDefaults.adminUser | quote) -}}
{{- printf "- %s\n" (printf "AMQPConnections.%s-connection.password=%s" $hub $v.edgeBrokerDefaults.adminPassword | quote) -}}
{{- printf "- %s\n" (printf "AMQPConnections.%s-connection.retryInterval=5000" $hub | quote) -}}
{{- printf "- %s\n" (printf "AMQPConnections.%s-connection.reconnectAttempts=-1" $hub | quote) -}}
{{- /* Bridge configurations (before federation per Josh's review) */ -}}
{{- printf "- %s\n" (printf "AMQPConnections.%s-connection.bridges.%s-bridge.type=BRIDGE" $hub $spoke.name | quote) -}}
{{- printf "- %s\n" (printf "AMQPConnections.%s-connection.bridges.%s-bridge.bridgeFromAddressPolicies.%s-to-%s-bridge-policy.useDurableSubscriptions=true" $hub $spoke.name $hub $spoke.name | quote) -}}
{{- printf "- %s\n" (printf "AMQPConnections.%s-connection.bridges.%s-bridge.bridgeFromAddressPolicies.%s-to-%s-bridge-policy.includeDivertBindings=false" $hub $spoke.name $hub $spoke.name | quote) -}}
{{- printf "- %s\n" (printf "AMQPConnections.%s-connection.bridges.%s-bridge.bridgeFromAddressPolicies.%s-to-%s-bridge-policy.includes.all.addressMatch=messages.ALL.#" $hub $spoke.name $hub $spoke.name | quote) -}}
{{- printf "- %s\n" (printf "AMQPConnections.%s-connection.bridges.%s-bridge.bridgeFromAddressPolicies.%s-to-%s-bridge-policy.includes.region.addressMatch=messages.%s.#" $hub $spoke.name $hub $spoke.name $spoke.region | quote) -}}
{{- printf "- %s\n" (printf "AMQPConnections.%s-connection.bridges.%s-bridge.bridgeFromAddressPolicies.%s-to-%s-bridge-policy.excludes.5604.addressMatch=messages.%s.5604" $hub $spoke.name $hub $spoke.name $spoke.region | quote) -}}
{{- printf "- %s\n" (printf "AMQPConnections.%s-connection.bridges.%s-bridge.bridgeToAddressPolicies.%s-to-%s-bridge-policy.useDurableSubscriptions=true" $hub $spoke.name $spoke.name $hub | quote) -}}
{{- printf "- %s\n" (printf "AMQPConnections.%s-connection.bridges.%s-bridge.bridgeToAddressPolicies.%s-to-%s-bridge-policy.includeDivertBindings=false" $hub $spoke.name $spoke.name $hub | quote) -}}
{{- printf "- %s\n" (printf "AMQPConnections.%s-connection.bridges.%s-bridge.bridgeToAddressPolicies.%s-to-%s-bridge-policy.includes.wild.addressMatch=messages.#" $hub $spoke.name $spoke.name $hub | quote) -}}
{{- printf "- %s\n" (printf "AMQPConnections.%s-connection.bridges.%s-bridge.bridgeToAddressPolicies.%s-to-%s-bridge-policy.excludes.all.addressMatch=messages.ALL.#" $hub $spoke.name $spoke.name $hub | quote) -}}
{{- printf "- %s\n" (printf "AMQPConnections.%s-connection.bridges.%s-bridge.bridgeToAddressPolicies.%s-to-%s-bridge-policy.excludes.region.addressMatch=messages.%s.#" $hub $spoke.name $spoke.name $hub $spoke.region | quote) -}}
{{- /* Federation configurations (remote policy only — no localAddressPolicies per Josh's review) */ -}}
{{- printf "- %s\n" (printf "AMQPConnections.%s-connection.federations.%s-federation.type=FEDERATION" $hub $spoke.name | quote) -}}
{{- printf "- %s\n" (printf "AMQPConnections.%s-connection.federations.%s-federation.remoteAddressPolicies.%s-to-%s-federation-policy.autoDelete=true" $hub $spoke.name $spoke.name $hub | quote) -}}
{{- printf "- %s\n" (printf "AMQPConnections.%s-connection.federations.%s-federation.remoteAddressPolicies.%s-to-%s-federation-policy.autoDeleteDelay=0" $hub $spoke.name $spoke.name $hub | quote) -}}
{{- printf "- %s\n" (printf "AMQPConnections.%s-connection.federations.%s-federation.remoteAddressPolicies.%s-to-%s-federation-policy.autoDeleteMessageCount=1000" $hub $spoke.name $spoke.name $hub | quote) -}}
{{- printf "- %s\n" (printf "AMQPConnections.%s-connection.federations.%s-federation.remoteAddressPolicies.%s-to-%s-federation-policy.maxHops=1" $hub $spoke.name $spoke.name $hub | quote) -}}
{{- printf "- %s\n" (printf "AMQPConnections.%s-connection.federations.%s-federation.remoteAddressPolicies.%s-to-%s-federation-policy.includes.5604.addressMatch=messages.%s.5604" $hub $spoke.name $spoke.name $hub $spoke.region | quote) -}}
{{- end }}
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
