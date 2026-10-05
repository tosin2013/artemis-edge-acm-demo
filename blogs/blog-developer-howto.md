# Edge messaging with Red Hat AMQ Broker: deploy and federate brokers across clusters using RHACM and GitOps

Edge sites need reliable messaging, but manually installing and configuring brokers on dozens of single-node OpenShift (SNO) clusters does not scale. I have spent enough time SSH-ing into remote clusters to know that a better approach exists.

In this article, I walk you through a pattern that uses Red Hat Advanced Cluster Management for Kubernetes (RHACM) governance policies and a GitOps workflow to deploy Red Hat AMQ Broker across an edge fleet, federate messages back to a central hub, and monitor every broker from a single Grafana dashboard. By the end, you will have a clear picture of how to manage messaging infrastructure across edge sites without touching each cluster individually.

The architecture is straightforward: one RHACM hub cluster runs a central AMQ Broker instance called `hub-01`, while each SNO edge cluster runs a spoke broker that federates messages to the hub over AMQPS (AMQP over TLS).

## Prerequisites

Before you start, you need:

- A Red Hat OpenShift Container Platform cluster running RHACM 2.x in the hub role
- One or more SNO edge clusters managed by the hub (or the ability to provision them with Hive)
- The AMQ Broker Operator available from the Red Hat operators catalog
- Red Hat OpenShift GitOps (Argo CD) installed on the hub
- Familiarity with Kubernetes custom resources and the `oc` CLI

## Understand the federation topology

The hub-and-spoke model keeps things simple. The central broker, `hub-01`, runs on the RHACM hub cluster in the `artemis` namespace. It accepts AMQPS connections from edge brokers through an OpenShift passthrough Route. Each SNO edge site runs one AMQ Broker instance — `spoke-01` for New York, `spoke-02` for New Jersey, and so on.

Federation flows in one direction: each spoke pushes regional messages to the hub. A spoke broker declares a connection called `hub-01-connection` that federates selected address patterns (for example, `messages.NY.#`) to the central broker using AMQP federation over TLS. A consumer connected to `hub-01` receives messages from any edge site.

The configuration sets `maxHops=1` to prevent message loops between spokes. Address patterns control which messages federate and which stay local on the SNO — you decide what leaves the edge and what does not.

## Deploy the AMQ Broker operator to edge clusters with RHACM policies and GitOps

### Define policies in a Helm chart synced by Argo CD

All AMQ resources for the edge live in a Helm chart on the hub, synced by an Argo CD application called `field-content`. The chart renders RHACM Policy and Placement objects into the `edge-broker-policies` namespace. No YAML is hand-applied to any spoke cluster.

Three policy layers handle the full deployment:

1. **`policy-amq-broker-operator-sno`** creates the `artemis` Namespace, OperatorGroup, and AMQ Broker Subscription on every cluster labeled `sites: edge-sno`. This installs the operator.

2. **`policy-amq-broker-spoke-<N>`** creates a per-region `ActiveMQArtemis` custom resource with the correct AMQPS federation configuration pointing to `hub-01`.

3. **`policy-sno-uwl-amq-metrics`** (optional) enables user-workload monitoring on each SNO so broker metrics reach Thanos for centralized observability.

Each policy uses the `enforce` remediation action, which means RHACM continuously reconciles drift. If someone deletes a resource on an edge cluster, the policy recreates it automatically.

### How RHACM Placement selects edge clusters

Placement rules use label selectors like `sites: edge-sno` and `edge-region: NY` to target the right clusters. When a new SNO joins and receives the correct labels, policies apply automatically — no chart change needed. This is how the pattern scales from two sites to hundreds without manual intervention.

```yaml
# Simplified Placement example
apiVersion: cluster.open-cluster-management.io/v1beta1
kind: Placement
metadata:
  name: policy-amq-broker-spoke-01-placement
  namespace: edge-broker-policies
spec:
  predicates:
    - requiredClusterSelector:
        labelSelector:
          matchLabels:
            sites: edge-sno
            edge-region: NY
```

## Produce and consume messages across hub and edge sites

The end-to-end message path works like this: an application on the New York SNO publishes to `topic://messages.NY.test`. The spoke broker's federation pushes the message over AMQPS to `hub-01`. A consumer connected to `hub-01` receives it.

Start the consumer on the hub first — topic (multicast) subscriptions only receive messages sent after the subscription is created:

```bash
/opt/amq/bin/artemis consumer \
  --url=amqp://hub-01-broker-amqp-acceptor-0-svc.artemis.svc.cluster.local:5672 \
  --protocol=AMQP --user=admin --password=admin \
  --destination=topic://messages.NY.test --message-count=5
```

Then produce from the New York SNO using the AMQPS Route:

```bash
/opt/amq/bin/artemis producer \
  --url='amqps://spoke-01-broker-amqps-acceptor-0-svc-rte-artemis.apps.sno-edge-01.example.com:443?sslEnabled=true&transport.trustAll=true&transport.verifyHost=false&useTopologyForLoadBalancing=false' \
  --protocol=AMQP --user=admin --password=admin \
  --message-count=5 --message='hello from NY SNO' \
  --destination=topic://messages.NY.test
```

The hub consumer prints five received messages. The same pattern works for any number of regions — New Jersey messages arrive on a `messages.NJ.*` address, and a Connecticut spoke would use `messages.CT.*`.

## Monitor edge brokers with Grafana and multicluster observability

RHACM Multicluster Observability aggregates Prometheus metrics from all managed clusters into a central Thanos and Grafana stack on the hub. A custom Grafana dashboard called **AMQ Broker – Artemis Edge**, deployed as a ConfigMap, gives you five panels at a glance:

- **Queue message counts** (`artemis_message_count`) — see messages accumulating per broker and queue
- **Messages added and acknowledged rates** — track throughput across the fleet
- **Connection count** — confirm federation connections from spokes are active
- **Address memory usage** — compare against the 1 GiB `globalMaxSize` limit
- **Consumer count** — monitor active consumers per address

The **Cluster** dropdown at the top of the dashboard lets you filter by `local-cluster` (the hub), `sno-edge-01` (New York), or `sno-edge-02` (New Jersey) to compare edge sites side by side.

For proactive alerting, deploy custom Thanos Ruler rules as a ConfigMap. For example, a `BrokerQueueDepthHigh` alert fires when `artemis_message_count` exceeds 1,000 messages for two minutes, and a `BrokerMemoryUsageHigh` alert fires when address memory crosses 80% of the configured maximum.

## Tips and best practices

- At scale, replace per-spoke Helm entries with PolicyGenerator and `fromClusterClaim` to manage hundreds of edge sites without growing your values file.
- Use `enforce` remediation so RHACM auto-remediates drift. Use `inform` only when you want to monitor without correcting.
- Pin the AMQ Broker Operator to a specific channel (for example, `7.14.x`) so edge upgrades stay predictable.
- Test federation by producing a small batch and verifying it arrives at the hub before rolling out to production sites.
- Keep the `ztp-policies` ApplicationSet unbound — binding it syncs the full hub Helm chart to every SNO, which is not what you want.

## Wrap up

I covered a GitOps-driven, policy-based approach to deploying AMQ Broker across an edge fleet. RHACM policies install the operator and configure per-region federation automatically. Messages flow from edge SNOs to a central hub over AMQPS, and multicluster observability gives you a centralized view of broker health, queue depth, and throughput for the entire fleet.

This pattern scales from two SNOs to hundreds without touching each cluster individually. The combination of Argo CD for hub-side GitOps and RHACM governance policies for edge-side enforcement keeps your messaging infrastructure consistent and auditable.

Ready to try it yourself? Explore the official documentation to go deeper:

- [Red Hat Advanced Cluster Management for Kubernetes documentation](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/)
- [Red Hat AMQ Broker documentation](https://docs.redhat.com/en/documentation/red_hat_amq_broker/)
- [Deploying AMQ Broker on OpenShift](https://docs.redhat.com/en/documentation/red_hat_amq_broker/7.12/html/deploying_amq_broker_on_openshift/)

For the full hands-on workshop that this article is based on, see the [Artemis Edge ACM Demo](https://github.com/tosin2013/artemis-edge-acm-demo) on GitHub.

---

## Metadata

| Field | Value |
|---|---|
| **Meta title** | Deploy AMQ Broker across edge clusters with ACM & GitOps |
| **Meta description** | Learn how to deploy Red Hat AMQ Broker on edge clusters using RHACM policies and Argo CD, federate messages to a central hub, and monitor broker health. |
| **URL slug** | `/blog/deploy-amq-broker-edge-clusters-acm-gitops` |
| **Suggested image alt text** | Network diagram showing an ACM hub cluster with a central AMQ Broker connected to three SNO edge clusters via AMQPS federation, with Argo CD syncing policies and Grafana collecting metrics |
| **Word count** | ~1,170 |
