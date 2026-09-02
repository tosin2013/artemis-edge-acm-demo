# Architecture

## Deployment Modes

### Mode 1: Single Hub

- 1 RHACM hub cluster with ArgoCD, Keycloak, Prometheus, Grafana
- 2 hub AMQ Brokers (hub-01, hub-02) for HA
- 3 SNO edge clusters (NY, NJ, CT regions)
- Each edge cluster runs an AMQ Broker with AMQP federation to the hub

### Mode 2: Multi Hub (Global Hub)

- 1 Multicluster Global Hub cluster
- 2 regional RHACM hub clusters, each with its own hub brokers
- 3 SNO edge clusters per regional hub (6 total)
- Global Hub provides fleet-of-fleets observability

## Messaging Topology

Edge brokers use AMQP federation to connect to hub brokers:

- **Local policies**: Pull `messages.ALL.#` and own region from hub
- **Remote policies**: Push all messages except own region + ALL to hub
- **Special policy**: `messages.*.5604` with `maxHops=1`

Federation supports TLS-encrypted AMQP over port 443 with automatic reconnection (`reconnectAttempts=-1`).

## Address Routing

| Address Pattern | Description |
|----------------|-------------|
| `messages.NY.#` | New York region messages |
| `messages.NJ.#` | New Jersey region messages |
| `messages.CT.#` | Connecticut region messages |
| `messages.ALL.#` | Broadcast to all brokers |
| `messages.*.5604` | Special routing with maxHops=1 |

## Security

- **TLS**: JKS keystores/truststores for broker-to-broker and client communication
- **OIDC**: Keycloak with `artemis-keycloak` realm, `artemis-broker` and `artemis-console` clients
- **JAAS**: `login.config` chains PropertiesLoginModule + DirectAccessGrantsLoginModule
- **Roles**: `admin` (full), `producer` (send), `consumer` (receive)

## Zero Touch Provisioning

SNO clusters are provisioned via RHACM:

1. SiteConfig defines cluster topology (GCP n2-standard-8 or Azure Standard_D8s_v5)
2. PolicyGenerator applies day-2 configuration (namespace, operator subscriptions)
3. Placement API targets clusters with `sites: edge-sno` label
4. ArgoCD ApplicationSet deploys edge workloads via cluster decision resource

## Cloud Providers

| | GCP | Azure |
|---|-----|-------|
| SNO Instance | n2-standard-8 | Standard_D8s_v5 |
| Hub Instance | n2-standard-16 | Standard_D8s_v5 |
| Storage | pd-ssd | managed-premium |
| Disk | 120Gi | 120Gi |
