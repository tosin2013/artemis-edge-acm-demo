# Blog outline: AMQ Broker at the edge with ACM and GitOps

## Meta

| Field | Value |
|---|---|
| **Proposed title** | Edge messaging with AMQ Broker: How to deploy and federate brokers across clusters using Red Hat ACM and GitOps |
| **Meta title** | Deploy AMQ Broker across edge clusters with ACM & GitOps |
| **Meta description** | Learn how to deploy AMQ Broker on edge clusters using Red Hat Advanced Cluster Management policies and GitOps, federate messages to a central hub, and monitor broker health with Grafana. |
| **URL slug** | `/blog/deploy-amq-broker-edge-clusters-acm-gitops` |
| **Template** | How-to Article |
| **Word count target** | 800–1300 words |
| **Audience** | Application developers, SREs |
| **SEO keywords** | edge computing, AMQ Broker, Red Hat Advanced Cluster Management, GitOps, Kubernetes, OpenShift, SNO |

---

## Outline

### Introduction (100–150 words)

**Hook — what is in it for the reader:**

- Open with the challenge: edge sites need reliable messaging, but manually installing and configuring brokers on dozens (or hundreds) of single-node OpenShift (SNO) clusters does not scale.
- State the payoff: by the end of this article, readers will know how to use Red Hat Advanced Cluster Management (RHACM) governance policies and a GitOps workflow to deploy AMQ Broker across edge clusters, federate messages back to a central hub, and monitor the whole fleet from a single Grafana dashboard.
- Briefly introduce the architecture: one ACM hub cluster running a central AMQ Broker (`hub-01`) plus N SNO edge clusters, each running a spoke broker that federates to the hub over AMQPS.
- Set the scope: this article walks through the key concepts and steps — a full hands-on lab is linked at the end.

---

### H2: Prerequisites (50–75 words)

Key bullets:

- An OpenShift cluster running RHACM 2.x (hub role)
- One or more SNO edge clusters managed by the hub (or the ability to provision them with Hive)
- The AMQ Broker Operator available from the Red Hat operators catalog
- OpenShift GitOps (ArgoCD) installed on the hub
- Familiarity with Kubernetes custom resources and the `oc` CLI

---

### H2: Understand the federation topology (150–200 words)

> *This section covers the agenda item: Show AMQ Hub broker and AMQ Spoke brokers, federation topology*

Key bullets:

- Describe the hub-and-spoke model:
  - `hub-01` — the central AMQ Broker instance running on the ACM hub cluster in namespace `artemis`. Accepts AMQPS connections from edge brokers via an OpenShift passthrough Route.
  - `spoke-*` — one AMQ Broker per SNO edge site. Each spoke declares a broker connection (`hub-01-connection`) that federates selected address patterns (e.g., `messages.NY.#`) to the hub using AMQP federation over TLS.
- Explain the federation direction: each spoke *pushes* regional messages to the hub. A consumer on the hub receives messages from any edge site.
- Note `maxHops=1` to prevent message loops between spokes.
- Mention that address patterns control which messages federate and which stay local on the SNO.

#### Proposed architecture diagram

> **Diagram description:** A network-style diagram showing the ACM hub cluster at the center with `hub-01` AMQ Broker. Two (or three) SNO edge clusters (labeled NY, NJ, CT) are shown at the periphery, each with a spoke AMQ Broker. Dashed arrows labeled "AMQPS federation" point from each spoke inward to `hub-01`. An ArgoCD icon on the hub cluster has an arrow labeled "GitOps sync" pointing to an `edge-broker-policies` box. An RHACM shield icon has arrows labeled "Policy enforce" pointing to each SNO. A Grafana icon on the hub has dotted lines labeled "metrics" coming from every cluster. A small consumer icon sits next to `hub-01` receiving messages from all regions.

---

### H2: Deploy the AMQ Broker operator to edge clusters with ACM policies and GitOps (200–250 words)

> *This section covers the agenda item: Using GitOps show how the ACM Hub can install the Operator across all spokes*

#### H3: Define policies in a Helm chart synced by ArgoCD

Key bullets:

- Explain that all AMQ resources for the edge live in a Helm chart on the hub, synced by the ArgoCD application `field-content`.
- The chart renders RHACM Policy + Placement objects into the `edge-broker-policies` namespace. No YAML is hand-applied.
- Walk through the three policy layers:
  1. **`policy-amq-broker-operator-sno`** — creates the `artemis` Namespace, OperatorGroup, and AMQ Broker Subscription on every cluster labeled `sites: edge-sno`. This is the operator install.
  2. **`policy-amq-broker-spoke-<N>`** — creates a per-region `ActiveMQArtemis` CR with the correct AMQPS federation configuration to `hub-01`.
  3. **(optional) `policy-sno-uwl-amq-metrics`** — enables user-workload monitoring on each SNO so broker metrics reach Thanos.

#### H3: How ACM Placement selects edge clusters

Key bullets:

- Placement rules use label selectors (`sites: edge-sno`, `edge-region: NY|NJ|CT`) to target the right clusters.
- As new SNOs join and are labeled, policies auto-apply — no chart change needed.
- Mention the enforce remediation action: ACM will continuously reconcile drift.

---

### H2: Produce and consume messages across hub and edge sites (150–200 words)

> *This section covers the agenda item: Produce and consume messages across hub and edge sites*

Key bullets:

- Explain the end-to-end message path: an application on the NY SNO publishes to `topic://messages.NY.test` → the spoke broker's federation pushes the message over AMQPS to `hub-01` → a consumer connected to `hub-01` receives it.
- Show a simplified produce command (CLI snippet using the `artemis` CLI or an AMQP client) pointing at the SNO's AMQPS Route.
- Show a simplified consume command against `hub-01` inside the cluster (AMQP, no TLS needed for in-cluster).
- Highlight that the consumer must subscribe *before* producing (multicast/topic semantics).
- Note that the same pattern works for any number of regions — NJ messages arrive on a `messages.NJ.*` address, and so on.

---

### H2: Monitor edge brokers with Grafana and multicluster observability (150–200 words)

> *This section covers the agenda item: Show metrics of AMQ being up on spokes via Grafana dashboard*

Key bullets:

- Introduce RHACM Multicluster Observability (MCO): aggregates Prometheus metrics from all managed clusters into a central Thanos + Grafana stack on the hub.
- Describe the custom **AMQ Broker – Artemis Edge** Grafana dashboard deployed as a ConfigMap. Five panels:
  1. Queue message counts (`artemis_message_count`)
  2. Messages added and acknowledged rates
  3. Connection count (shows federation connections from spokes)
  4. Address memory usage (compare against the 1 GiB global max)
  5. Consumer count per address
- Emphasize the **Cluster dropdown**: filter by `local-cluster` (hub), `sno-edge-01` (NY), or `sno-edge-02` (NJ) to compare edge sites side by side.
- Mention custom Thanos Ruler alerts (e.g., `BrokerQueueDepthHigh` when `artemis_message_count > 1000`) deployed as a ConfigMap alongside the dashboard.

---

### H2: Tips and best practices (75–100 words)

Key bullets:

- At scale, replace per-spoke Helm entries with PolicyGenerator and `fromClusterClaim` for hundreds of edge sites.
- Use `enforce` remediation so ACM auto-remediates drift; `inform` only reports.
- Keep the `ztp-policies` ApplicationSet unbound — binding it syncs the full hub chart to every SNO.
- Test federation by producing a small batch and verifying it arrives at the hub before going to production.
- Pin the AMQ Broker Operator to a specific channel (e.g., `7.14.x`) so edge upgrades are predictable.

---

### H2: Wrap up (75–100 words)

Key bullets:

- Summarize what the reader learned: a GitOps-driven, policy-based approach to deploying AMQ Broker across an edge fleet, with automatic federation and centralized observability.
- Reinforce the value: this pattern scales from two SNOs to hundreds without touching each cluster individually.
- Transition to the CTA.

---

### Call to action

**CTA text (link to docs.redhat.com):**

> Ready to try it yourself? Explore the official documentation to go deeper:
>
> - [Red Hat Advanced Cluster Management documentation](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/)
> - [AMQ Broker documentation](https://docs.redhat.com/en/documentation/red_hat_amq_broker/)
> - [Deploying AMQ Broker on OpenShift](https://docs.redhat.com/en/documentation/red_hat_amq_broker/7.12/html/deploying_amq_broker_on_openshift/)
>
> For the full hands-on workshop that this article is based on, see the [Artemis Edge ACM Demo](https://github.com/tosin2013/artemis-edge-acm-demo) on GitHub.

---

## Word count estimate

| Section | Est. words |
|---|---|
| Introduction | 100–150 |
| Prerequisites | 50–75 |
| Understand the federation topology | 150–200 |
| Deploy the AMQ Broker operator with ACM policies and GitOps | 200–250 |
| Produce and consume messages across hub and edge sites | 150–200 |
| Monitor edge brokers with Grafana and multicluster observability | 150–200 |
| Tips and best practices | 75–100 |
| Wrap up and CTA | 75–100 |
| **Total** | **~950–1275** |
