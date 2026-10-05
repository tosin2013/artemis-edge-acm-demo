# AMQ Broker Delivery Mechanisms

This repository contains **four distinct mechanisms** for deploying AMQ Broker
to OpenShift clusters. They are **not alternatives** — each serves a specific
deployment mode and tier. This document explains when each is active, how they
relate, and which to use.

## Quick Reference

| # | Mechanism | Directory | Active In | Delivers To | Technology |
|---|-----------|-----------|-----------|-------------|------------|
| 1 | **Helm Chart Templates** | `templates/` | Mode 1 + Mode 2 | Hub cluster (direct) | Helm + ArgoCD |
| 2 | **ACM ApplicationSet** | `acm/` | Mode 1 (reference) | Edge SNOs via ACM | ArgoCD ApplicationSet |
| 3 | **ZTP PolicyGenerator** | `ztp/` | Reference only | Edge SNOs via PolicyGen | Kustomize + PolicyGenerator |
| 4 | **Fleet GitOps** | `fleet-gitops/` | Mode 2 only | Regional hubs + SNOs | Kustomize + ArgoCD + ACM OperatorPolicy |

## Deployment Flow by Mode

### Mode 1 — Single ACM Hub

```
┌─────────────────────────────────────────────────┐
│  ACM Hub Cluster                                │
│                                                 │
│  ArgoCD ──── Helm chart (templates/) ──────┐    │
│              ├─ AMQ Operator Subscription   │    │
│              ├─ hub-01 Broker CR            │    │
│              ├─ edge-broker-policies ────── │ ─┐ │
│              ├─ Keycloak                    │  │ │
│              ├─ Showroom                    │  │ │
│              └─ Monitoring                  │  │ │
│                                             │  │ │
│  spoke-01, spoke-02, spoke-03 (local)  ◄────┘  │ │
└─────────────────────────────────────────────────┘ │
                                                    │
   Student SNOs  ◄── ACM ConfigurationPolicy ───────┘
   (spoke-01..03)    (from edge-broker-policies.yaml)
```

**Active mechanisms:**
- **Mechanism 1 (Helm):** Deploys everything on the hub — operator, hub
  broker, spoke brokers (running locally), Keycloak, Showroom, monitoring.
- **Mechanism 1 (Helm) `edge-broker-policies.yaml`:** When
  `spokeProvisioning.enabled=true`, emits ACM ConfigurationPolicy to deploy
  AMQ operator + broker CRs onto student SNOs.

**Not active:**
- Mechanism 2 (`acm/`) — Reference/aspirational. Not wired in Mode 1.
- Mechanism 3 (`ztp/`) — Reference only. Same intent as edge-broker-policies
  but using PolicyGenerator syntax.
- Mechanism 4 (`fleet-gitops/`) — Mode 2 only (`globalHub.enabled=false`).

### Mode 2 — Hub-of-Hubs (Multi-Hub)

```
┌──────────────────────────────────┐
│  Global Hub (Tier 0)             │
│  No AMQ brokers                  │
│                                  │
│  ArgoCD ─── fleet-gitops/ ───────┤──── push ────┐
│             (Mechanism 4)        │              │
│  templates/fleet-gitops-app.yaml │              │
│  (Mechanism 1 triggers Mech. 4)  │              │
└──────────────────────────────────┘              │
                                                  ▼
  ┌─────────────────────────────────────────────────┐
  │  Regional ACM Hub (Tier 1) × 3                  │
  │  (east, central, west)                          │
  │                                                 │
  │  Helm chart (templates/) ──── Mechanism 1       │
  │  ├─ AMQ Operator (OperatorPolicy via Mech. 4)   │
  │  ├─ hub-01 Broker CR                            │
  │  ├─ edge-broker-policies ─────────────────── ─┐ │
  │  └─ Keycloak, Showroom, Monitoring            │ │
  │                                               │ │
  │  fleet-gitops/hubs/ ── Mechanism 4            │ │
  │  ├─ applicationset-amq.yaml (pull to SNOs)    │ │
  │  ├─ policy-amq-broker-operator.yaml           │ │
  │  └─ placement + bindings                      │ │
  └───────────────────────────────────────────────┘ │
                                                    │
    Student SNOs (Tier 2)  ◄────────────────────────┘
    ├─ AMQ Operator (OperatorPolicy from Mech. 4)
    ├─ Site broker (ConfigurationPolicy from Mech. 1)
    └─ Federation → regional hub-01
```

**Active mechanisms:**
- **Mechanism 1 (Helm):** Deploys on each regional hub (operator, hub broker,
  edge-broker-policies, Keycloak, Showroom). On Global Hub, it only emits
  `fleet-gitops-app.yaml` (the ArgoCD Application that triggers Mechanism 4).
- **Mechanism 4 (Fleet GitOps):** Push from Global Hub to regional hubs
  (`fleet-gitops/applicationsets/hubs.yaml`). Pull from regional hubs to
  SNOs (`fleet-gitops/hubs/base/applicationset-amq.yaml`). Delivers
  OperatorPolicy for AMQ, UWM, and GitOps operators.

**Not active:**
- Mechanism 2 (`acm/`) — Superseded by Mechanism 4.
- Mechanism 3 (`ztp/`) — Reference only.

## Detailed Mechanism Descriptions

### Mechanism 1: Helm Chart Templates (`templates/`)

The core delivery method. ArgoCD on each cluster runs `helm template` against
this repo with the appropriate values overlay.

| What it deploys | Template file(s) |
|---|---|
| AMQ Broker Operator subscription | `amq-broker-operator.yaml` |
| Hub broker (ActiveMQArtemis CR) | `hub-broker.yaml`, `hub-broker-properties.yaml` |
| Hub broker TLS secrets | `hub-broker-tls.yaml` |
| Hub broker monitoring | `hub-broker-prometheus-svc.yaml` |
| Edge broker ACM policies (for SNOs) | `edge-broker-policies.yaml` |
| Spoke RHACM policies | `spoke-rhacm-policies.yaml` |
| Fleet GitOps trigger (Mode 2 Global Hub) | `fleet-gitops-app.yaml` |
| Keycloak | `keycloak-*.yaml` |
| Showroom | `showroom.yaml` |
| Workshop RBAC | `workshop-user-rbac.yaml` |

**Values overlays:**
- `values.yaml` — Mode 1 (single hub, local spoke brokers)
- `values-mode2.yaml` — Mode 2 regional hub (AMQ hub + SNO provisioning)
- `values-mode2-global.yaml` — Mode 2 Global Hub (no brokers, fleet-gitops only)

### Mechanism 2: ACM ApplicationSet (`acm/`)

An **older pattern** that uses an ArgoCD ApplicationSet with ACM Placement
to deploy this Helm chart onto placed clusters.

| File | Purpose |
|---|---|
| `acm/applicationset.yaml` | ApplicationSet that renders this chart on matched SNOs |
| `acm/policies/amq-broker-policy.yaml` | ACM Policy delivering AMQ Operator subscription |
| `acm/policies/monitoring-policy.yaml` | ACM Policy for monitoring config |

**Status:** Reference only. This was the original multi-cluster approach before
`edge-broker-policies.yaml` (Mechanism 1) and `fleet-gitops/` (Mechanism 4)
were implemented. The ApplicationSet is not bound to any Placement in the
active chart.

### Mechanism 3: ZTP PolicyGenerator (`ztp/`)

Uses RHACM PolicyGenerator (a Kustomize plugin) to generate ACM policies
that deliver AMQ Broker to edge SNOs.

| File | Purpose |
|---|---|
| `ztp/policygenerator/policy-generator.yaml` | PolicyGenerator config (sites: `edge-sno`) |
| `ztp/policygenerator/edge-broker/amq-broker-subscription.yaml` | AMQ Operator Subscription manifest |
| `ztp/policygenerator/common/namespace.yaml` | `artemis` namespace |
| `ztp/siteconfigs/sno-gcp-template.yaml` | SiteConfig for GCP SNOs |
| `ztp/siteconfigs/sno-azure-template.yaml` | SiteConfig for Azure SNOs |

**Status:** Reference only. Provides the same functionality as
`edge-broker-policies.yaml` but in PolicyGenerator syntax. Useful as a
reference for teams that prefer the ZTP workflow over direct Helm-rendered
ConfigurationPolicy.

### Mechanism 4: Fleet GitOps (`fleet-gitops/`)

Mode 2 App-of-Apps with a **push + pull** pattern.

**Push layer** (Global Hub → Regional Hubs):
| File | Purpose |
|---|---|
| `fleet-gitops/applicationsets/hubs.yaml` | ApplicationSet targeting 3 regional hubs |
| `fleet-gitops/platform/policies/*.yaml` | OperatorPolicy for AMQ, UWM, GitOps on regional hubs |
| `fleet-gitops/platform/placements/*.yaml` | Placement + binding for all managed hubs |

**Pull layer** (Regional Hub → SNOs):
| File | Purpose |
|---|---|
| `fleet-gitops/hubs/base/applicationset-amq.yaml` | Pull-mode ApplicationSet for SNO AMQ |
| `fleet-gitops/hubs/base/policy-amq-broker-operator.yaml` | OperatorPolicy for AMQ on SNOs |
| `fleet-gitops/hubs/base/placement-all-amq-sites.yaml` | Placement for edge-sno sites |
| `fleet-gitops/hubs/overlays/{east,central,west}/` | Per-region Kustomize overlays |

**Trigger:** `templates/fleet-gitops-app.yaml` creates an ArgoCD Application
pointing at `fleet-gitops/` when `globalHub.enabled=true`.

## FAQ

### Are mechanisms 1–4 alternatives (pick one)?

**No.** Mechanism 1 is always active. Mechanism 4 is the multi-hub extension.
Mechanisms 2 and 3 are reference implementations of alternative approaches.

### Do `acm/` and `ztp/` overlap with `fleet-gitops/`?

Yes, in intent — they all deliver AMQ to edge clusters. In practice:
- `fleet-gitops/` is the **active** Mode 2 approach (OperatorPolicy-based)
- `acm/` is the **original** approach (ApplicationSet-based, superseded)
- `ztp/` is a **reference** (PolicyGenerator-based, never wired)

### Why do both `edge-broker-policies.yaml` and `ztp/` emit AMQ policies?

`edge-broker-policies.yaml` is the Helm-rendered version that's actually
deployed. `ztp/policygenerator/` provides the same manifests in
PolicyGenerator format for teams that use the ZTP workflow. They are not
deployed simultaneously.

### Which files should I modify?

| If you're changing... | Edit these |
|---|---|
| Hub broker config | `templates/hub-broker*.yaml`, `values.yaml` |
| Edge broker federation | `templates/edge-broker-policies.yaml`, `_helpers.tpl` |
| Mode 2 operator delivery | `fleet-gitops/hubs/base/policy-*.yaml` |
| Mode 2 regional hub setup | `fleet-gitops/platform/policies/*.yaml` |
| Reference ACM approach | `acm/` (not actively deployed) |
| Reference ZTP approach | `ztp/` (not actively deployed) |
