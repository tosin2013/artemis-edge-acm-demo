# Artemis Edge ACM Demo

Federated AMQ Broker messaging across RHACM-managed Single Node OpenShift (SNO) edge clusters. This repository is a **Field-Sourced Content** Helm chart for the Red Hat Demo Platform (RHDP).

## What This Demo Shows

- **AMQP Federation**: Edge brokers route regional messages (`messages.NY.#`, `messages.NJ.#`, `messages.CT.#`) to hub brokers with store-and-forward resilience
- **Zero Touch Provisioning**: RHACM provisions SNO edge clusters via SiteConfig + PolicyGenerator
- **GitOps Deployment**: ArgoCD ApplicationSet deploys edge workloads across the fleet
- **Observability**: Prometheus + Grafana monitor all brokers with a unified AMQ dashboard
- **OIDC Security**: Keycloak provides OIDC authentication for broker access (alice=producer, bob=consumer)

## Deployment Modes

| Mode | Clusters | Description |
|------|----------|-------------|
| Mode 1 (Single Hub) | 1 hub + 3 SNO | Quick validation of edge-to-hub federation |
| Mode 2 (Multi Hub) | 1 Global Hub + 2 hubs + 6 SNO | Cross-hub federation with fleet-of-fleets observability |

## Quick Start

### Automated Setup

```bash
./bootstrap.sh
```

The bootstrap script checks prerequisites, configures your deployment, generates TLS certificates, and validates your environment.

### Manual Setup

1. **Generate TLS certificates:**

```bash
export KC_DOMAIN=apps.hub.example.com
export HUB01_DOMAIN=apps.hub.example.com
./scripts/generate-tls.sh
```

2. **Deploy Mode 1 (Single Hub):**

```bash
helm install artemis-edge . \
  --values values.yaml \
  --set global.clusterDomain=apps.hub.example.com \
  --set keycloak.clientSecret=YOUR_SECRET
```

3. **Deploy Mode 2 (Multi Hub):**

```bash
helm install artemis-edge . \
  --values values.yaml \
  --values values-mode2.yaml \
  --set global.clusterDomain=apps.hub.example.com \
  --set keycloak.clientSecret=YOUR_SECRET
```

4. **Cloud-specific overlays:**

```bash
# GCP
helm install artemis-edge . -f values.yaml -f values-gcp.yaml

# Azure
helm install artemis-edge . -f values.yaml -f values-azure.yaml
```

## Repository Structure

```
├── Chart.yaml                     # Helm chart metadata
├── values.yaml                    # Mode 1 defaults (single hub, 3 SNO)
├── values-mode2.yaml              # Mode 2 overlay (multi-hub, 6 SNO)
├── values-gcp.yaml                # GCP instance types + storage
├── values-azure.yaml              # Azure instance types + storage
├── templates/                     # All Helm templates
├── ztp/                           # ZTP: SiteConfigs, PolicyGenerator, Placement
├── acm/                           # ACM: ApplicationSet + policies
├── showroom/                      # Draft Showroom lab guide (Antora)
├── java/                          # Quarkus Camel clients (AMQP, MQTT, bridge)
├── scripts/                       # TLS generation, setup utilities
├── upstream-ref/                  # Original fork files for reference
├── onboard.yml                    # Project onboarding manifest
├── bootstrap.sh                   # Standalone setup script
└── docs/                          # Architecture documentation
```

## Values Reference

| Key | Default | Description |
|-----|---------|-------------|
| `global.mode` | `single-hub` | Deployment mode: `single-hub` or `multi-hub` |
| `global.clusterDomain` | `""` | OpenShift cluster ingress domain |
| `hubBrokers` | 1 broker | List of hub AMQ Broker instances |
| `edgeBrokers` | 3 spokes | List of edge brokers with region assignments |
| `keycloak.enabled` | `true` | Deploy Keycloak OIDC provider |
| `keycloak.clientSecret` | `""` | Keycloak broker client secret |
| `monitoring.enabled` | `true` | Deploy Prometheus + Grafana |
| `globalHub.enabled` | `false` | Deploy Multicluster Global Hub (Mode 2) |
| `showroom.enabled` | `true` | Deploy Showroom lab guide |

## Demo Credentials

| User | Password | Role |
|------|----------|------|
| admin | admin | Broker admin |
| alice | bosco | Producer |
| bob | bosco | Consumer |

## Showroom Lab Guide

The `showroom/` directory contains an Antora-based lab guide with 8 modules covering the full demo flow. Preview locally:

```bash
podman run --rm --name antora -v $PWD/showroom:/antora:z -p 8080:8080 -i -t \
  ghcr.io/juliaaano/antora-viewer
```

## Java Clients

The `java/` directory preserves the Quarkus Camel applications from the upstream fork:

- **amqp-client**: AMQP producer/consumer
- **mqtt-client**: MQTT5 producer/consumer
- **amqp-bridge**: Durable subscription bridge with loop prevention
- **artemis-extensions**: StaticHeaderPlugin for broker-side header injection

Build: `cd java/amqp-client && mvn package -Dquarkus.container-image.build=true`

## Credits

Based on [joshdreagan/artemis-edge-demo](https://github.com/joshdreagan/artemis-edge-demo), extended with RHACM integration, ZTP, and Field-Sourced Content packaging.
