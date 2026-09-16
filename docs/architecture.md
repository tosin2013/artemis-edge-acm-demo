# Architecture

Two planes. Do not use “hub” for both.

- **ACM hub** — a management cluster (Global Hub or a regional ACM hub).
- **AMQ hub** — an Artemis broker that site brokers federate to. It lives on a **regional ACM hub**, never on Global Hub.

Mode 1 (tag `mode-1`) is one ACM hub plus student-provisioned SNOs. This page describes **Mode 2**.

Source: [AMQ_Fleet_Control_Blueprint.pdf](../AMQ_Fleet_Control_Blueprint.pdf) (rev 2, 15 Sep 2026).

## Tiers

| Tier | Clusters | Who deploys | What it does |
|------|----------|-------------|--------------|
| 0 Global Hub | 1, GCP | AgnosticD | Multicluster Global Hub: inventory, policy replication, **compliance Grafana (PostgreSQL)**. Argo CD **push** of `hubs/<region>` to the three regional hubs. Extra **Thanos Query + Grafana** for fleet AMQ metrics (not GH Grafana). No AMQ broker. Sites never talk here. |
| 1 Regional ACM hubs | 3 (east, central, west) | AgnosticD | Full ACM. MCO/Thanos + regional GCS. Fleet ApplicationSet **pull** to sites. **One AMQ hub broker** on this cluster. |
| 2 Sites (SNO) | Student-created | Module 2 (`deploy-spokes.sh` / ACM import) | klusterlet, small Argo CD, AMQ operator + **site broker**, User Workload Monitoring. Outbound only. |

AgnosticD does **not** create SNOs. After Module 2, Global Hub inventory lists the new site under the regional hub that imported it.

```
                    Global Hub (T0)
                    GH Grafana = compliance
                    Thanos Query = fleet AMQ (queries 3 regions)
                           |
              Argo CD push | GH agent (outbound from regionals)
              +------------+------------+
              |            |            |
         ACM east     ACM central    ACM west     (T1)
         MCO Grafana  MCO Grafana    MCO Grafana
         AMQ hub      AMQ hub        AMQ hub
              |            |            |
           SNOs         SNOs          SNOs        (T2, student)
           site AMQ     site AMQ      site AMQ
```

## GitOps

- **Push** Global Hub → 3 regional hubs (`fleet-gitops/applicationsets/hubs.yaml`). Three targets, all in GCP.
- **Pull** regional hub → SNOs (`fleet-gitops/hubs/base/applicationset-amq.yaml`). Hub never opens a site API. Needs GitOps Operator 1.9.0+ (`skip-reconcile`).
- **Policies** for platform (OperatorPolicy, UWM, namespace). **Git `brokerProperties`** for site addresses — not `ActiveMQArtemisAddress` / `ActiveMQArtemisSecurity` (deprecated in AMQ Broker 7.12).
- Region Git tags (`fleet-east`, `fleet-central`, `fleet-west`) are the promotion boundary.

## Metrics

ACM MCO/Thanos is **per ACM hub**. Regional Grafana sees that region only.

Global Hub Grafana does **not** merge `artemis_*`. Fleet AMQ view is a Thanos Query on the global hub whose stores are the three regional Thanos Query gRPC endpoints (passthrough + mTLS; extra engineering, not a GH feature).

Allowlist at the site (`uwl_metrics_list.yaml`); store in the region; global querier stores nothing.

## Messaging overlay (5603–5607)

Each site federates to **its** regional AMQ hub. First slice: one AMQ hub per region (no cross-region standby).

| Class | Meaning |
|-------|---------|
| 5603 | Internal spoke only (must not leave the SNO) |
| 5604 | Spoke and that region’s AMQ hub, not other SNOs (`maxHops=1`) |
| 5605 | Spoke to spoke via the regional AMQ hub |
| 5606 | Regional AMQ hub to all SNOs in that region (`messages.ALL.5606`) |
| 5607 | Regional AMQ hub to one SNO (`messages.{region}.5607`) |

Cookie-cutter brokers; apps pick `messages.{REGION\|ALL}.{class}`.

## Mode 1 (unchanged)

- 1 RHACM hub, student SNOs (NY/NJ, optional CT)
- SNO AMQ federates to hub-01 AMQPS on that same ACM hub
- MCO Grafana on that hub (`cluster=local-cluster` vs `sno-edge-*`)
