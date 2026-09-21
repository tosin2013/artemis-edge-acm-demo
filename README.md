# Artemis Edge ACM Demo

Federated AMQ Broker messaging across RHACM-managed Single Node OpenShift (SNO)
edge clusters. This repository is a **Field-Sourced Content** Helm chart for the
Red Hat Demo Platform (RHDP).

## What This Demo Shows

- **AMQP Federation** — Edge brokers route regional messages to hub brokers with store-and-forward resilience
- **Zero Touch Provisioning** — RHACM provisions SNO edge clusters via SiteConfig + PolicyGenerator
- **GitOps Deployment** — ArgoCD ApplicationSet deploys edge workloads across the fleet
- **Observability** — Prometheus + Grafana monitor all brokers with a unified AMQ dashboard
- **OIDC Security** — Keycloak provides OIDC authentication for broker access

## Lab guide preview

A static Antora preview of the Showroom lab guide is published to GitHub Pages:

https://tosin2013.github.io/artemis-edge-acm-demo/

That preview uses example hostnames (`guid: example`). It is **not** a live workshop: no terminal, no cluster login, no substituted GUID. Students still use Showroom on the hub after `agd provision`.

## Quick Start

One command goes from zero to a fully deployed demo:

```bash
git clone https://github.com/tosin2013/artemis-edge-acm-demo.git
cd artemis-edge-acm-demo
./bootstrap.sh
```

The bootstrap script reads [`onboard.yml`](onboard.yml) at runtime and:

1. Installs prerequisites (Python 3.12, Podman, Helm, gcloud, Java 21, etc.)
2. Clones [AgnosticD v2](https://github.com/tosin2013/agnosticd-v2) and runs `agd setup`
3. Copies vars and scaffolds secrets files
4. Generates TLS certificates
5. Prompts for configuration (GUID, cloud provider, domain)
6. Validates your environment
7. Deploys via `agd provision` (in prod mode)

### Non-Interactive Deploy

```bash
./bootstrap.sh --deploy
```

Uses all defaults from `onboard.yml` and `config.yml` — no prompts.

### Dev Mode (Contributors)

```bash
./bootstrap.sh --mode dev
```

Installs extra tools (ShellCheck, yamllint) for linting and testing.

### Check-Only

```bash
./bootstrap.sh --check-only
```

Runs validation checks without installing or deploying anything.

## Deployment Modes

| Mode | What AgnosticD creates | What students create | Description |
|------|------------------------|----------------------|-------------|
| Mode 1 (single-hub) | 1 ACM hub | SNOs in Module 2 | Edge-to-hub AMQP federation on one ACM hub |
| Mode 2 (multi-hub) | 1 Global Hub + 3 regional ACM hubs (east/central/west) | SNOs in Module 2 onto a **regional** hub | ACM hub-of-hubs control plane; one AMQ hub broker **per regional ACM hub**; GH Grafana is compliance only |

See [docs/architecture.md](docs/architecture.md) and [agnosticd/gcp/MODE2.md](agnosticd/gcp/MODE2.md). The architecture blueprint PDF is a local file (`AMQ_Fleet_Control_Blueprint.pdf`), not in git. SNOs are never created at `agd provision` time.

## How It Works

```
bootstrap.sh --mode prod
  └─ reads onboard.yml
     └─ installs prerequisites
     └─ runs setup steps (clone agnosticd-v2, agd setup, scaffold secrets)
     └─ prompts for config (GUID, domain, etc.)
     └─ validates environment
     └─ calls deploy.sh
        └─ cd agnosticd-v2 && agd provision -g GUID -c artemis-edge-gcp -a ACCOUNT
           └─ ansible-navigator (EE container)
              └─ Step 001: GCP infrastructure (bastion VM)
              └─ Step 004: Install OpenShift
              └─ Step 005: Deploy workloads
                 ├─ cert-manager
                 ├─ htpasswd auth
                 ├─ RHACM
                 ├─ OpenShift GitOps (ArgoCD)
                 ├─ Field Content (Artemis Edge Helm chart)
                 └─ Showroom (lab guide)
```

## Lifecycle Operations

```bash
# Provision (default)
./scripts/deploy.sh --guid 725j2 --account openenv-gcp

# Stop cluster (save costs)
./scripts/stop.sh --guid 725j2

# Start cluster
./scripts/start.sh --guid 725j2

# Check status
./scripts/deploy.sh --status --guid 725j2

# Destroy
./scripts/teardown.sh --guid 725j2
```

Or use `agd` directly:

```bash
cd ~/Development/agnosticd-v2
./bin/agd provision -g 725j2 -c artemis-edge-gcp -a openenv-gcp
./bin/agd destroy   -g 725j2 -c artemis-edge-gcp -a openenv-gcp
```

## Repository Structure

```
├── Chart.yaml                     # Helm chart metadata
├── values.yaml                    # Mode 1 defaults (single ACM hub)
├── values-mode2.yaml              # Mode 2 overlay for a *regional* ACM hub (one AMQ hub, student SNOs)
├── values-mode2-global.yaml       # Mode 2 overlay for Global Hub (no AMQ broker, no SNOs)
├── fleet-gitops/                  # Push to 3 regional hubs; pull to SNOs; OperatorPolicy
├── values-gcp.yaml                # GCP instance types + storage
├── values-azure.yaml              # Azure instance types + storage
├── templates/                     # All Helm templates
├── ztp/                           # ZTP: SiteConfigs, PolicyGenerator, Placement
├── acm/                           # ACM: ApplicationSet + policies
├── showroom/                      # Showroom lab guide (Antora)
├── java/                          # Quarkus Camel clients (AMQP, MQTT, bridge)
├── agnosticd/gcp/                 # AgnosticD vars (Mode 1, Mode 2 GH, Mode 2 regional)
├── scripts/                       # deploy.sh, start/stop/teardown, TLS gen
├── onboard.yml                    # Onboarding manifest (single source of truth)
├── bootstrap.sh                   # Standalone setup script (reads onboard.yml)
├── CONTRIBUTING.md                # Contributor guidelines
└── LICENSE                        # Apache-2.0
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
| `globalHub.enabled` | `false` | Global Hub operator (Tier 0 cluster only; no AMQ broker) |
| `fleetThanosQuery.enabled` | `false` | Extra Thanos Query + Grafana for fleet AMQ metrics on Global Hub |
| `showroom.enabled` | `true` | Deploy Showroom lab guide |

## Demo Credentials

| User | Password | Role |
|------|----------|------|
| admin | admin | Broker admin |
| alice | bosco | Producer |
| bob | bosco | Consumer |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, code standards,
and the pull request workflow.

## License

[Apache-2.0](LICENSE)

## Credits

Based on [joshdreagan/artemis-edge-demo](https://github.com/joshdreagan/artemis-edge-demo),
extended with RHACM integration, ZTP, and Field-Sourced Content packaging.
