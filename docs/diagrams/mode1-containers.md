# Mode 1 Container Diagram (Single ACM Hub)

Mode 1 deploys one ACM hub cluster with all platform services. Students
provision SNO edge clusters in Module 2. Each SNO runs a site AMQ broker
that federates to the hub broker over AMQPS.

```mermaid
flowchart TB
    subgraph HubCluster ["ACM Hub Cluster (single-hub)"]
        RHACM["RHACM
        Manages SNO imports,
        policies, placements"]

        ArgoCD["OpenShift GitOps
        Syncs Helm chart,
        ApplicationSet to SNOs"]

        subgraph ArtemisNS ["Namespace: artemis"]
            HubBroker["Hub Broker (hub-01)
            ActiveMQArtemis CR
            AMQPS acceptor for federation"]

            HubMonitor["ServiceMonitor
            Scrapes artemis_* metrics"]
        end

        subgraph KeycloakNS ["Namespace: keycloak"]
            Keycloak["Keycloak + PostgreSQL
            OIDC provider for
            broker authentication"]
        end

        subgraph MonitoringNS ["Observability"]
            MCO["MCO / Thanos
            Cluster and user-workload
            metrics collection"]

            Grafana["Grafana Dashboard
            AMQ broker metrics,
            cluster filter"]
        end

        subgraph ShowroomNS ["Namespace: showroom"]
            ShowroomApp["Showroom
            Lab guide + terminal
            for demo attendees"]
        end

        AMQOp["AMQ Broker Operator
        Reconciles ActiveMQArtemis CRs"]

        CertMgr["cert-manager
        TLS certificates for
        brokers and Keycloak"]
    end

    subgraph SNO1 ["SNO Edge: spoke-01 (NY)"]
        SiteBroker1["Site Broker (spoke-01)
        ActiveMQArtemis CR
        Federates to hub-01"]
        SiteMon1["ServiceMonitor
        artemis_* metrics"]
        Klusterlet1["klusterlet
        ACM agent"]
    end

    subgraph SNO2 ["SNO Edge: spoke-02 (NJ)"]
        SiteBroker2["Site Broker (spoke-02)
        ActiveMQArtemis CR
        Federates to hub-01"]
        SiteMon2["ServiceMonitor
        artemis_* metrics"]
        Klusterlet2["klusterlet
        ACM agent"]
    end

    RHACM -->|"import, label,
    apply policies"| Klusterlet1
    RHACM -->|"import, label,
    apply policies"| Klusterlet2

    ArgoCD -->|"sync Helm chart"| ArtemisNS
    ArgoCD -->|"ApplicationSet
    to edge SNOs"| SNO1
    ArgoCD -->|"ApplicationSet
    to edge SNOs"| SNO2

    SiteBroker1 -->|"AMQPS federation
    (outbound)"| HubBroker
    SiteBroker2 -->|"AMQPS federation
    (outbound)"| HubBroker

    HubBroker -->|"OIDC authn"| Keycloak
    HubMonitor -->|"scrape"| HubBroker
    MCO -->|"collect"| HubMonitor
    MCO -->|"remote-write
    from SNOs"| SiteMon1
    MCO -->|"remote-write
    from SNOs"| SiteMon2
    Grafana -->|"query"| MCO

    CertMgr -->|"issue certs"| HubBroker
    CertMgr -->|"issue certs"| Keycloak
```

## Legend

| Component | Description |
|-----------|-------------|
| **Hub Broker (hub-01)** | Central AMQ Artemis broker. Accepts AMQPS federation from edge site brokers. |
| **Site Broker** | Edge AMQ Artemis broker on each SNO. Federates outbound to hub-01. |
| **RHACM** | Red Hat Advanced Cluster Management. Imports and manages SNO clusters. |
| **OpenShift GitOps** | Argo CD instance. Syncs the Helm chart on the hub and ApplicationSet to SNOs. |
| **Keycloak** | OIDC identity provider. Authenticates broker clients (admin, alice, bob). |
| **MCO / Thanos** | Monitoring stack. Collects metrics from hub and remote-writes from SNOs. |
| **Grafana** | AMQ dashboard ConfigMap. Shows broker metrics filtered by cluster. |
| **cert-manager** | Issues TLS certificates for broker AMQPS and Keycloak HTTPS. |
| **Showroom** | Lab guide application with embedded terminal for demo attendees. |

## Key Points

- All SNO connections are **outbound** from the edge to the hub.
- Federation uses AMQPS (TLS) on the hub broker acceptor.
- A single MCO/Thanos instance on the hub collects metrics from all clusters.
- Grafana filters by `cluster` label to distinguish `local-cluster` from `sno-edge-*`.
