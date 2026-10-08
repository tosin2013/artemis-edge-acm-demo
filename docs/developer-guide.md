# Developer Guide

This guide is for developers who modify the Helm chart, add edge regions,
change broker configurations, build Java clients, or contribute to this
repository.

## Table of Contents

- [Repository Layout](#repository-layout)
- [Helm Development](#helm-development)
- [Adding a New Edge Region (Mode 2)](#adding-a-new-edge-region-mode-2)
- [Broker Configuration](#broker-configuration)
- [Java Clients](#java-clients)
- [CI/CD Pipelines](#cicd-pipelines)
- [ArgoCD Prerequisites](#argocd-prerequisites)
- [Testing Changes](#testing-changes)

---

## Repository Layout

```
artemis-edge-acm-demo/
├── Chart.yaml                          # Helm chart metadata (v0.1.0)
├── values.yaml                         # Mode 1 defaults (base)
├── values-mode2.yaml                   # Regional hub overlay
├── values-mode2-global.yaml            # Global Hub overlay
├── values-gcp.yaml                     # GCP machine types
├── values-azure.yaml                   # Azure machine types
│
├── templates/                          # Helm templates (40+ files)
│   ├── _helpers.tpl                    # Template helpers
│   ├── namespaces.yaml                 # Wave 0: namespaces
│   ├── operator-groups.yaml            # Wave 0: OperatorGroups
│   ├── amq-broker-operator-sub.yaml    # Wave 1: AMQ Operator
│   ├── keycloak-operator-sub.yaml      # Wave 1: Keycloak Operator
│   ├── cert-manager-*.yaml             # Waves 1-3: TLS
│   ├── wait-for-crds.yaml              # Waves 2-3: CRD readiness gates
│   ├── hub-broker*.yaml                # Wave 4: Hub broker + config
│   ├── edge-broker*.yaml               # Wave 4: Edge broker + config
│   ├── keycloak*.yaml                  # Waves 4-5: Keycloak stack
│   ├── edge-broker-policies.yaml       # Waves 5-6: ACM policies
│   ├── global-hub*.yaml                # Global Hub operator (Mode 2)
│   ├── fleet-gitops-app.yaml           # Wave 5: fleet-gitops Argo App
│   ├── fleet-thanos-query.yaml         # Fleet Thanos Query (Mode 2)
│   ├── showroom*.yaml                  # Showroom + terminal RBAC
│   └── service-monitors.yaml           # Prometheus ServiceMonitors
│
├── fleet-gitops/                       # Mode 2 App-of-Apps
│   ├── applicationsets/hubs.yaml       # Push: Global Hub to regionals
│   ├── hubs/
│   │   ├── base/                       # Pull ApplicationSet, policies
│   │   └── overlays/{east,central,west}/ # Region patches (targetRevision)
│   ├── amq/
│   │   ├── base/broker.yaml            # Cookie-cutter site broker
│   │   └── overlays/site-class/small/  # Site-class overlay
│   └── platform/
│       ├── policies/                   # OperatorPolicy sources
│       └── placements/                 # Hub and site placements
│
├── acm/                                # Standalone ACM resources
│   ├── applicationset.yaml             # ACM-driven ApplicationSet
│   └── policies/                       # Reference AMQ + monitoring policies
│
├── ztp/                                # Zero Touch Provisioning scaffolds
│   ├── siteconfigs/                    # SiteConfig templates (GCP, Azure)
│   ├── policygenerator/                # PolicyGenerator for edge sites
│   └── placement/                      # Edge SNO placement
│
├── showroom/                           # Antora lab guide
│   └── content/modules/ROOT/           # AsciiDoc modules 0-8
│
├── java/                               # Quarkus Camel clients
│   ├── amqp-client/                    # AMQP producer/consumer
│   ├── mqtt-client/                    # MQTT producer/consumer
│   ├── amqp-bridge/                    # AMQP bridge (hub-to-site relay)
│   └── artemis-extensions/             # Artemis plugin (static headers)
│
├── scripts/                            # Lifecycle and utility scripts
├── agnosticd/gcp/                      # AgnosticD vars per mode/tier
├── bootstrap.sh                        # One-command setup entry point
├── onboard.yml                         # Onboarding manifest
└── .github/workflows/                  # CI: Helm lint + Showroom Pages
```

---

## Helm Development

### Local Validation

Run `helm lint` and `helm template` locally before committing:

```bash
# Lint the chart
helm lint .

# Template with Mode 1 defaults
helm template test . \
  --set global.clusterDomain=dev.example.com \
  --set global.clusterApiUrl=https://api.dev.example.com:6443

# Template with Mode 2 Global Hub overlay
helm template test . \
  -f values-mode2-global.yaml \
  --set global.clusterDomain=dev.example.com

# Template with Mode 2 Regional overlay
helm template test . \
  -f values-mode2.yaml \
  --set global.clusterDomain=dev.example.com \
  --set global.region=east
```

### Adding a New Template

1. Create the template file in `templates/`.
2. Add the appropriate sync-wave annotation:
   ```yaml
   metadata:
     annotations:
       argocd.argoproj.io/sync-wave: "4"
   ```
3. Gate the template with a values condition if it is optional:
   ```yaml
   {{- if .Values.myFeature.enabled }}
   ...
   {{- end }}
   ```
4. Add the corresponding values key to `values.yaml` with a sensible default.
5. Run `helm lint` and `helm template` to verify.

### Sync-Wave Reference

| Wave | What belongs here |
|------|-------------------|
| 0 | Namespaces, OperatorGroups, ConfigMaps that other resources depend on |
| 1 | Operator Subscriptions, cert-manager Issuers |
| 2 | Certificate CRs, CRD-wait Jobs, Secrets |
| 3 | Resources that need CRDs from wave 1 operators (pre-broker) |
| 4 | Core workloads: broker CRs, Keycloak CR |
| 5 | Post-workload: realm import, RBAC, ACM policies, fleet-gitops App |
| 6 | Resources that depend on wave 5 (PlacementBindings after Placements) |

### Values Overlay Pattern

Do not add mode-specific logic to `values.yaml`. Create or extend an overlay file instead.

- `values.yaml` = universal defaults. Every deployment loads this.
- `values-mode2.yaml` = overrides for a regional hub. Merged on top of `values.yaml`.
- `values-mode2-global.yaml` = overrides for the Global Hub. Merged on top of `values.yaml`.

AgnosticD passes the correct `-f` flags at deploy time based on `--mode` and `--tier`.

---

## Adding a New Edge Region (Mode 2)

To add a fourth region (for example, `south`):

### 1. Create the regional overlay

```bash
mkdir -p fleet-gitops/hubs/overlays/south
```

Create a `kustomization.yaml` that patches `targetRevision` to `fleet-south`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
patches:
  - target:
      kind: ApplicationSet
      name: amq-fleet
    patch: |
      - op: replace
        path: /spec/generators/0/clusterDecisionResource/requeueAfterSeconds
        value: 180
      - op: replace
        path: /spec/template/spec/source/targetRevision
        value: fleet-south
```

### 2. Update the hubs ApplicationSet

Edit `fleet-gitops/applicationsets/hubs.yaml`. Add `south` to the directory list or verify the Placement matches clusters labeled `region: south`.

### 3. Create the region Git tag

```bash
git tag fleet-south
git push origin fleet-south
```

### 4. Create AgnosticD vars

Copy `agnosticd/gcp/mode2-east-vars.yml` to `agnosticd/gcp/mode2-south-vars.yml` and update the region name.

### 5. Label the new hub cluster

After provisioning, label the regional hub on the Global Hub:

```bash
oc label managedcluster south-<SANDBOX> \
  hub-tier=regional \
  region=south
```

### 6. Update import script

Add the new hub to `scripts/import-managed-hubs.sh` or extend it to auto-discover hubs by label.

---

## Broker Configuration

### brokerProperties vs Deprecated CRs

AMQ Broker 7.12 deprecates `ActiveMQArtemisAddress` and `ActiveMQArtemisSecurity` custom resources. This project uses `brokerProperties` secrets instead.

The `brokerProperties` secret is a key-value map that maps directly to Artemis broker properties. The Helm chart generates these secrets in:

- `templates/hub-broker-properties.yaml` -- hub broker address and security config
- `templates/edge-broker-properties.yaml` -- edge broker federation connectors and address policies

Site brokers in `fleet-gitops/amq/base/broker.yaml` also use `brokerProperties`.

### Address Class Scheme

Messages use the pattern `messages.{REGION|ALL}.{CLASS}`:

| Class | Routing | maxHops |
|-------|---------|---------|
| 5603 | Site-local only | 0 |
| 5604 | Site to regional hub | 1 |
| 5605 | Site to site via hub | 2 |
| 5606 | Hub broadcast to all sites | 1 |
| 5607 | Hub to one specific site | 1 |

See [Message Federation diagram](diagrams/message-federation.md) for the full flow.

### Federation Wiring

Each site broker connects outbound to its regional hub over AMQPS. The connection is defined in the site `brokerProperties`:

- Connector: points to the hub broker AMQPS route.
- Federation upstream: references the connector.
- Address policies: define which address patterns to federate and the hop count.

The hub broker has a corresponding AMQPS acceptor that is enabled when `spokeProvisioning.enabled: true`.

---

## Java Clients

Four Quarkus Camel projects live in `java/`:

| Project | Purpose | Protocol |
|---------|---------|----------|
| `amqp-client` | AMQP producer and consumer | AMQP 1.0 |
| `mqtt-client` | MQTT producer and consumer | MQTT 5.0 |
| `amqp-bridge` | Hub-to-site message relay | AMQP 1.0 |
| `artemis-extensions` | Artemis broker plugin (static headers) | Broker plugin |

### Build and Run

```bash
cd java/amqp-client
mvn clean package -DskipTests

# Run locally (needs AMQP endpoint)
mvn quarkus:dev \
  -Damqp.host=localhost \
  -Damqp.port=5672 \
  -Damqp.user=alice \
  -Damqp.password=bosco
```

### Key Classes

| Class | Location | Role |
|-------|----------|------|
| `CamelConfiguration` | `amqp-client/.../CamelConfiguration.java` | Camel route builder for AMQP produce/consume |
| `CamelConfiguration` | `mqtt-client/.../CamelConfiguration.java` | Camel route builder for MQTT produce/consume |
| `CamelConfiguration` | `amqp-bridge/.../CamelConfiguration.java` | Camel route builder for hub-site message relay |
| `Mode` | `amqp-client/.../config/Mode.java` | Producer or consumer mode enum |
| `StaticHeaderPlugin` | `artemis-extensions/.../StaticHeaderPlugin.java` | Artemis plugin that adds static headers to messages |

### Configuration

All clients use Quarkus configuration properties. Set via environment variables or `application.properties`:

| Property | Description |
|----------|-------------|
| `amqp.host` | Broker hostname |
| `amqp.port` | Broker port (5672 for AMQP, 61617 for AMQPS) |
| `amqp.user` | Authentication username |
| `amqp.password` | Authentication password |
| `app.mode` | `PRODUCER` or `CONSUMER` |
| `app.address` | Target address (for example, `messages.NY.5604`) |

---

## CI/CD Pipelines

Two GitHub Actions workflows run on this repository.

### Helm Chart Validation

**File**: `.github/workflows/helm-validate.yaml`

**Triggers**: Push or PR to `main` that changes `Chart.yaml`, `values.yaml`, or `templates/**`.

**Steps**:
1. Checkout the repo.
2. Install Helm.
3. Run `helm lint .`
4. Run `helm template test .` with test values.

This workflow validates that the chart is syntactically correct and renders without errors.

### Showroom GitHub Pages

**File**: `.github/workflows/showroom-gh-pages.yaml`

**Triggers**: Push to `main` that changes `showroom/**`, or manual dispatch.

**Steps**:
1. Checkout the repo.
2. Install Node.js and Antora.
3. Build the Showroom site with example GUID substitution.
4. Deploy to GitHub Pages.

The published site is at https://tosin2013.github.io/artemis-edge-acm-demo/. It is a static preview only.

---

## ArgoCD Prerequisites

The Helm chart relies on several ArgoCD configuration items that are **not**
part of the chart itself.  These must be applied to each hub cluster after
OpenShift GitOps is installed.  The script
`scripts/patch-argocd-health-check.sh` automates all three items below
(called automatically by `post-provision-multihub.sh` step 3).

### ApplicationSet Health Check

The `artemis-edge-workloads` ApplicationSet in sync wave 5 is
**intentionally unbound** (Option C / #48).  Without a custom health
check ArgoCD reports it as `Progressing` forever, stalling the entire
sync.  The health check always reports `Healthy` for ApplicationSet
resources so the sync can proceed:

```
resource.customizations.health.argoproj.io_ApplicationSet
```

### ApplicationSet Controller

OpenShift GitOps does not start the ApplicationSet controller unless the
ArgoCD CR has a `spec.applicationSet` section with resource requests.
The script patches the CR to enable it:

```yaml
spec:
  applicationSet:
    resources:
      limits:   { cpu: "1",    memory: "1Gi"   }
      requests: { cpu: "250m", memory: "512Mi" }
```

### `acm-placement` ConfigMap

The `clusterDecisionResource` generator in the ApplicationSet needs a
ConfigMap named `acm-placement` in `openshift-gitops` to duck-type
`PlacementDecision` resources.  The Helm chart creates this ConfigMap at
sync wave 0 (see `templates/acm-placement-configmap.yaml`, gated by
`spokeProvisioning.enabled`).  In Mode 2, the `GitOpsCluster` resource
may also auto-create it via the RHACM integration.

### Application Health Check

The existing `resource.customizations.health.argoproj.io_Application`
check ensures ArgoCD waits for child Applications to be Healthy before
proceeding to the next sync wave (App-of-Apps ordering).

---

## Testing Changes

### Helm Chart Changes

1. Run `helm lint .` to catch syntax errors.
2. Run `helm template test .` with each values overlay to verify rendering.
3. Push to a branch and verify the Helm Validation CI passes.
4. Deploy to a GCP sandbox and verify Argo CD syncs the chart.

### Fleet-GitOps Changes

1. Verify Kustomize builds cleanly:
   ```bash
   kustomize build fleet-gitops/hubs/overlays/east
   kustomize build fleet-gitops/amq/overlays/site-class/small
   ```
2. Push to a branch and update the region tag:
   ```bash
   git tag -f fleet-east
   git push -f origin fleet-east
   ```
3. Verify the regional hub Argo CD picks up the change.

### Showroom Changes

1. Edit AsciiDoc files in `showroom/content/modules/ROOT/pages/`.
2. Preview locally with Antora:
   ```bash
   cd showroom
   npx antora site.yml
   ```
3. Push to `main` and verify the GitHub Pages workflow publishes the update.

### Java Client Changes

1. Build and run unit tests:
   ```bash
   cd java/amqp-client
   mvn clean verify
   ```
2. Test against a local or remote broker:
   ```bash
   mvn quarkus:dev -Damqp.host=<BROKER_HOST>
   ```

### Full Integration Test

Deploy to a sandbox, provision spokes, run all eight Showroom modules, and verify:
- All brokers are running and federated.
- Messages flow through each address class.
- Grafana dashboard shows metrics for all clusters.
- Global Hub (Mode 2) shows regional hubs in inventory.
