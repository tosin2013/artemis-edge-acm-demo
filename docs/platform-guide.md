# Platform Engineer Guide

This guide is for platform engineers who deploy, operate, and extend the
Artemis Edge ACM Demo. It is not a lab walkthrough. For the hands-on demo,
use Showroom on the hub cluster.

## Table of Contents

- [System Overview](#system-overview)
- [Prerequisites](#prerequisites)
- [Deployment Quick Reference](#deployment-quick-reference)
- [Configuration Reference](#configuration-reference)
- [Helm Chart Anatomy](#helm-chart-anatomy)
- [Observability Stack](#observability-stack)
- [Troubleshooting](#troubleshooting)

---

## System Overview

This demo deploys federated AMQ Broker messaging across RHACM-managed
Single Node OpenShift (SNO) edge clusters. It runs as a Helm chart on
OpenShift, provisioned by AgnosticD v2 on GCP.

Two deployment modes are available:

| Mode | Clusters created by AgnosticD | What students create |
|------|-------------------------------|----------------------|
| **Mode 1** (single-hub) | 1 ACM hub | SNOs in Module 2 |
| **Mode 2** (multi-hub) | 1 Global Hub + 3 regional ACM hubs | SNOs onto a regional hub in Module 2 |

See the architecture diagrams for visual reference:

- [System Context](diagrams/c4-context.md) -- actors and external systems
- [Mode 1 Containers](diagrams/mode1-containers.md) -- single ACM hub layout
- [Mode 2 Containers](diagrams/mode2-containers.md) -- hub-of-hubs layout
- [GitOps Flow](diagrams/gitops-flow.md) -- push and pull model
- [Message Federation](diagrams/message-federation.md) -- address classes 5603-5607
- [Deployment Lifecycle](diagrams/deployment-lifecycle.md) -- bootstrap to teardown
- [Helm Components](diagrams/helm-components.md) -- template groups and sync waves

**Terminology:**
- **ACM hub** = a management cluster (Global Hub or regional ACM hub).
- **AMQ hub** = an Artemis broker that site brokers federate to. It lives on a regional ACM hub. The Global Hub never runs an AMQ broker.

---

## Prerequisites

### Tools

| Tool | Version | Purpose |
|------|---------|---------|
| `gcloud` | Latest | GCP CLI for authentication and DNS |
| `oc` | 4.14+ | OpenShift CLI |
| `helm` | 3.x | Chart validation and local testing |
| `ansible-navigator` | Latest | Run Ansible with execution environments |
| `java` | 21+ | Build Quarkus Camel clients |
| `mvn` | 3.9+ | Maven builds for Java clients |
| `podman` | Latest | Container runtime for execution environments |
| `python3` | 3.12+ | Bootstrap script runtime |

Run `./bootstrap.sh --check-only` to verify all tools are present.

### Accounts

- **GCP OpenEnv sandbox** with a service account key (`gcp-key.json`).
- **Red Hat pull secret** from [console.redhat.com](https://console.redhat.com/openshift/install/pull-secret).
- **GitHub access** to this repo (for ArgoCD to sync the Helm chart).

### GCP Resources

Each OpenShift cluster requires:
- Compute: `n2-standard-8` (default) or `n2-standard-16` (GCP values overlay)
- Storage: `pd-ssd` for etcd and persistent volumes
- DNS: Zone auto-created by AgnosticD under the sandbox base domain

---

## Deployment Quick Reference

### Mode 1: Single Hub

```bash
# 1. Clone and bootstrap
git clone https://github.com/tosin2013/artemis-edge-acm-demo.git
cd artemis-edge-acm-demo
cp /path/to/your-key.json gcp-key.json
./bootstrap.sh

# 2. Deploy (auto-detects GUID from gcp-key.json)
./scripts/deploy.sh --guid <GUID> --account openenv-gcp

# 3. Provision SNO spokes (Module 2)
./scripts/deploy-spokes.sh

# 4. Teardown
./scripts/destroy-spokes.sh
./scripts/teardown.sh --guid <GUID>
```

### Mode 2: Hub-of-Hubs

Deploy four clusters in order: Global Hub, then three regional hubs.

```bash
# 1. Global Hub (Tier 0)
./scripts/deploy.sh --mode multi-hub --tier global --sandbox <SANDBOX>

# 2. Regional hubs (Tier 1) — run sequentially or in parallel
./scripts/deploy.sh --mode multi-hub --tier east --sandbox <SANDBOX>
./scripts/deploy.sh --mode multi-hub --tier central --sandbox <SANDBOX>
./scripts/deploy.sh --mode multi-hub --tier west --sandbox <SANDBOX>

# 3. Post-provision (fix cert-manager, import hubs)
./scripts/post-provision-multihub.sh

# 4. Provision SNO spokes on a regional hub
./scripts/deploy-spokes.sh

# 5. Teardown (reverse order)
./scripts/destroy-spokes.sh
./scripts/teardown.sh --mode multi-hub --tier east --sandbox <SANDBOX>
./scripts/teardown.sh --mode multi-hub --tier central --sandbox <SANDBOX>
./scripts/teardown.sh --mode multi-hub --tier west --sandbox <SANDBOX>
./scripts/teardown.sh --mode multi-hub --tier global --sandbox <SANDBOX>
```

### Script Reference

| Script | Purpose |
|--------|---------|
| `bootstrap.sh` | One-command setup. Reads `onboard.yml`, installs tools, scaffolds secrets, deploys. |
| `bootstrap.sh --deploy` | Non-interactive deploy. Uses existing `config.yml` defaults. |
| `bootstrap.sh --check-only` | Validate environment without installing or deploying. |
| `bootstrap.sh --reconfigure` | Re-prompt all config values (for switching sandboxes). |
| `scripts/deploy.sh` | Main provisioner. Wraps `agd provision`. |
| `scripts/deploy-spokes.sh` | Create SNO edge clusters via Hive (default: 2, max: 3). |
| `scripts/deploy-spokes.sh --status` | Check spoke provisioning progress. |
| `scripts/destroy-spokes.sh` | Remove SNO ClusterDeployments. |
| `scripts/post-provision-multihub.sh` | Mode 2 post-provision: cert-manager fix, Argo patch, hub import. |
| `scripts/start.sh` | Start a stopped cluster. |
| `scripts/stop.sh` | Stop a cluster to save costs. |
| `scripts/teardown.sh` | Destroy a cluster and release GCP resources. |
| `scripts/generate-tls.sh` | Generate TLS keystores and truststores. |
| `scripts/generate-secrets.sh` | Scaffold AgnosticD secrets from GCP key. |
| `scripts/validate-deployment.sh` | Post-deploy health gate. |
| `scripts/save-deployment-info.sh` | Write `deployment-info.yml` and `.md` from AgnosticD output. |

---

## Configuration Reference

The chart uses layered values files. The base is `values.yaml`. Overlays
add or override settings for each deployment scenario.

### Values File Layering

| File | When to use |
|------|-------------|
| `values.yaml` | Mode 1 defaults. Always loaded as the base. |
| `values-mode2.yaml` | Regional ACM hub (Mode 2 Tier 1). Sets `multi-hub`, `hubTier: regional`. |
| `values-mode2-global.yaml` | Global Hub (Mode 2 Tier 0). Enables Global Hub, disables brokers and Showroom. |
| `values-gcp.yaml` | GCP machine types and storage classes. |
| `values-azure.yaml` | Azure machine types and storage classes. |

### Key Configuration Knobs

| Key | Default | Description |
|-----|---------|-------------|
| `global.mode` | `single-hub` | `single-hub` or `multi-hub`. Controls Mode 1 vs Mode 2 behavior. |
| `global.hubTier` | (none) | Mode 2 only. `global` for Tier 0, `regional` for Tier 1. |
| `global.region` | (none) | Mode 2 only. `east`, `central`, or `west`. |
| `global.clusterDomain` | `""` | OpenShift ingress domain. Set by AgnosticD at deploy time. |
| `hubBrokers` | 1 broker | List of hub AMQ Broker instances. Empty on Global Hub. |
| `edgeBrokers` | 3 spokes | List of edge brokers with region and hub connection assignments. |
| `edgeBrokerDefaults` | (see values.yaml) | Default resource limits and credentials for all edge brokers. |
| `keycloak.enabled` | `true` | Deploy Keycloak OIDC provider. |
| `keycloak.clientSecret` | `""` | Keycloak client secret for broker OIDC. |
| `monitoring.enabled` | `true` | Deploy Prometheus ServiceMonitors and Grafana dashboard. |
| `monitoring.acmObservability.enabled` | `true` | Deploy ACM observability metrics allowlist. |
| `globalHub.enabled` | `false` | Deploy Multicluster Global Hub operator and CR. Mode 2 Tier 0 only. |
| `fleetThanosQuery.enabled` | `false` | Deploy Thanos Query + Grafana for fleet AMQ metrics. Mode 2 Tier 0 only. |
| `fleetThanosQuery.regionalStores` | `[]` | List of regional Thanos gRPC endpoints for fleet query. |
| `showroom.enabled` | `true` | Deploy Showroom lab guide on this cluster. |
| `showroom.contentRepoUrl` | `""` | Git repo URL for Showroom content. |
| `showroom.contentRepoRef` | `main` | Git ref for Showroom content. |
| `tls.enabled` | `false` | Use pre-generated TLS keystores. |
| `tls.certManager.enabled` | `true` | Use cert-manager to issue TLS certificates. |
| `externalSecrets.enabled` | `false` | Use External Secrets Operator with GCP Secret Manager. |
| `spokeProvisioning.enabled` | `false` | Enable Hive ClusterDeployment templates for SNO provisioning. |
| `spokeProvisioning.clusters` | `[]` | List of clusters to pre-create. Empty by default; `deploy-spokes.sh` adds clusters. |

---

## Helm Chart Anatomy

The repo root is the Helm chart. All templates are in `templates/`.

### Template Groups

| Group | Templates | Purpose |
|-------|-----------|---------|
| **Foundations** | `namespaces`, `operator-groups` | Namespaces and OperatorGroups (wave 0) |
| **Operators** | `amq-broker-operator-sub`, `keycloak-operator-sub`, `external-secrets-operator` | Operator Subscriptions (wave 1) |
| **Certificates** | `cert-manager-issuer`, `cert-manager-broker-certs`, `cert-manager-keycloak-cert` | TLS issuers and certificate CRs (waves 1-3) |
| **CRD Gates** | `wait-for-crds` | Jobs that block until operator CRDs are available (waves 2-3) |
| **Brokers** | `hub-broker`, `edge-broker`, `*-properties`, `*-tls`, `*-prometheus-svc` | AMQ Artemis CRs, config secrets, TLS, metrics (wave 4) |
| **Security** | `keycloak`, `keycloak-postgresql`, `keycloak-realm-import`, `keycloak-secrets`, `oidc-jaas-config` | Keycloak OIDC stack (waves 4-5) |
| **ACM Policies** | `edge-broker-policies`, `spoke-rhacm-policies`, `spoke-policies-namespace` | Policies and placements for edge brokers (waves 5-6) |
| **Observability** | `acm-amq-dashboard`, `acm-amq-alerts`, `service-monitors`, `observability-metrics-allowlist`, `fleet-thanos-query` | Grafana, alerts, metrics collection |
| **Global Hub** | `global-hub`, `global-hub-argocd-bridge`, `fleet-gitops-app` | Mode 2 Global Hub operator, bridge, fleet-gitops Application (wave 5) |
| **Lab** | `showroom`, `showroom-terminal-rbac`, `workshop-user-rbac`, `userinfo-configmap` | Showroom and student RBAC (wave 5) |

See [Helm Components diagram](diagrams/helm-components.md) for the full sync-wave ordering and conditional rendering map.

### Sync-Wave Order

| Wave | What deploys |
|------|-------------|
| 0 | Namespaces, OperatorGroups |
| 1 | Operator Subscriptions, cert-manager Issuers |
| 2 | Certificate CRs, CRD-wait Jobs, External Secrets Store |
| 3 | Keycloak cert, Hive ClusterDeployments |
| 4 | Hub and edge brokers, Keycloak |
| 5 | Realm import, RBAC, ACM policies, fleet-gitops App |
| 6 | PlacementBindings (after Placements exist) |

---

## Observability Stack

### Mode 1

One MCO/Thanos instance on the ACM hub collects metrics from all clusters.

- **Hub metrics**: `cluster=local-cluster` in Prometheus.
- **SNO metrics**: `cluster=sno-edge-*`. Remote-written to the hub via ACM observability.
- **Grafana dashboard**: ConfigMap `acm-amq-dashboard`. Filter by cluster label.
- **Metrics allowlist**: `observability-metrics-allowlist` ConfigMap. Allows `artemis_*` from user workloads.

### Mode 2

Each regional hub has its own MCO/Thanos. Regional Grafana sees only that region.

- **Regional metrics**: Same as Mode 1, per regional hub.
- **Fleet AMQ view**: A Thanos Query on the Global Hub queries all three regional Thanos stores via gRPC passthrough routes.
- **Global Hub Grafana**: Compliance data only (PostgreSQL-backed). Does not show `artemis_*` metrics.
- **Fleet Grafana**: Separate from GH Grafana. Shows federated `artemis_*` metrics across all regions.

### ServiceMonitor Configuration

ServiceMonitors scrape the `artemis-prometheus` port on each broker pod. The metrics are available at the `/metrics` endpoint with prefix `artemis_`.

---

## Troubleshooting

### Argo CD Application not syncing

**Symptom**: The `field-content` Application shows `OutOfSync` or `Degraded`.

**Check**:
```bash
oc get application field-content -n openshift-gitops -o yaml | grep -A5 status
```

**Common causes**:
- CRD not yet available. Verify `wait-for-crds` Jobs completed.
- Sync-wave ordering issue. Check that earlier waves are healthy.
- Git authentication failure. Verify the repo URL is accessible.

### Broker federation not connecting

**Symptom**: Site brokers show `Disconnected` in the Jolokia console.

**Check**:
```bash
oc get activemqartemis -n artemis -o yaml
oc logs -n artemis -l application=hub-01-broker-ss --tail=50
```

**Common causes**:
- TLS certificate mismatch. Regenerate with `scripts/generate-tls.sh`.
- AMQPS acceptor not configured on hub. Verify `spokeProvisioning.enabled: true` in values.
- DNS resolution failure. Verify the hub route is resolvable from the SNO.

### cert-manager zone mismatch (Mode 2)

**Symptom**: Certificates stay in `Pending` state. cert-manager logs show DNS zone not found.

**Fix**: Run `scripts/fix-cert-manager-zone.sh` or `scripts/post-provision-multihub.sh` (which calls it automatically).

The root cause is that each regional hub has a different DNS zone name, but the ClusterIssuer defaults to the Global Hub zone.

### SNO spoke provisioning stuck

**Symptom**: `deploy-spokes.sh --status` shows `Installing` for more than 60 minutes.

**Check**:
```bash
oc get clusterdeployment -A
oc get agentclusterinstall -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[*].message}{"\n"}{end}'
```

**Common causes**:
- GCP quota exceeded. Check GCP console for quota errors.
- Pull secret expired. Re-download from console.redhat.com.
- SSH key missing. Verify `~/.ssh/sno-edge-key` exists.

### Metrics not appearing in Grafana

**Symptom**: AMQ dashboard shows no data for SNO clusters.

**Check**:
```bash
oc get configmap -n openshift-user-workload-monitoring uwl-metrics-list -o yaml
oc get servicemonitor -n artemis
```

**Common causes**:
- `artemis_*` not in the metrics allowlist. Verify `observability-metrics-allowlist` deployed.
- ServiceMonitor label selector mismatch. Verify broker pods match the selector.
- User workload monitoring not enabled on the SNO. Check the `cluster-monitoring-config` ConfigMap.

### Global Hub not seeing regional hubs

**Symptom**: Global Hub inventory is empty after deploying regional hubs.

**Fix**: Run `scripts/import-managed-hubs.sh` (or `scripts/post-provision-multihub.sh`).

**Verify**:
```bash
oc get managedcluster --context global-hub
```

Each regional hub should appear with labels `hub-tier=regional` and `region=east|central|west`.
