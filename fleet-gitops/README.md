# fleet-gitops — Mode 2 App-of-Apps

Mode 2 GitOps configuration for the ACM hub-of-hubs and regional AMQ broker deployment.

Apply on the Global Hub after the three regional hubs are imported and labelled
`hub-tier=regional`, `region=east|central|west`.

## How It Works

Two-stage GitOps model:

- **Push**: Global Hub Argo CD pushes config to three regional ACM hubs (`applicationsets/hubs.yaml`).
- **Pull**: Each regional hub runs an ApplicationSet that pulls AMQ workloads onto student SNOs (`hubs/base/applicationset-amq.yaml`). Requires OpenShift GitOps Operator 1.9.0+ (`argocd.argoproj.io/skip-reconcile`).

Platform policies (OperatorPolicy + User Workload Monitoring) are pushed onto each regional hub alongside the pull ApplicationSet.

Site brokers use `brokerProperties` secrets (AMQ Broker 7.12). `ActiveMQArtemisAddress` and `ActiveMQArtemisSecurity` CRs are deprecated.

## Promotion Boundary

Region Git tags control what each regional hub syncs:

| Tag | Regional hub | Overlay |
|-----|--------------|---------|
| `fleet-east` | East | `hubs/overlays/east/` patches `targetRevision` to `fleet-east` |
| `fleet-central` | Central | `hubs/overlays/central/` patches `targetRevision` to `fleet-central` |
| `fleet-west` | West | `hubs/overlays/west/` patches `targetRevision` to `fleet-west` |

Move a tag forward to roll out changes to that region.

## Directory Layout

```
fleet-gitops/
├── kustomization.yaml                              Root kustomization
├── applicationsets/
│   ├── hubs.yaml                                   Global Hub → regional hub config (push)
│   └── appproject-platform.yaml                    AppProject for platform policies
│
├── hubs/
│   ├── base/
│   │   ├── kustomization.yaml                      Base kustomization for regional hubs
│   │   ├── applicationset-amq.yaml                 Pull ApplicationSet → SNOs (skip-reconcile)
│   │   ├── appproject-amq.yaml                     AppProject for AMQ workloads
│   │   ├── gitopscluster.yaml                      GitOpsCluster for SNO targeting
│   │   ├── placement-all-amq-sites.yaml            Placement: clusters labelled fleet=amq
│   │   ├── placementbinding-site-platform.yaml     PlacementBinding for site platform policies
│   │   ├── obs-allowlist.yaml                      Observability metrics allowlist
│   │   ├── policy-amq-broker-operator.yaml         OperatorPolicy: AMQ Broker on sites
│   │   ├── policy-enable-uwm.yaml                  OperatorPolicy: User Workload Monitoring
│   │   └── policy-openshift-gitops-operator.yaml   OperatorPolicy: GitOps on sites
│   └── overlays/
│       ├── east/kustomization.yaml                 Patches targetRevision → fleet-east
│       ├── central/kustomization.yaml              Patches targetRevision → fleet-central
│       └── west/kustomization.yaml                 Patches targetRevision → fleet-west
│
├── amq/
│   ├── base/
│   │   ├── kustomization.yaml                      Base kustomization for site AMQ
│   │   ├── broker.yaml                             Cookie-cutter ActiveMQArtemis (brokerProperties)
│   │   └── servicemonitor.yaml                     ServiceMonitor for artemis_* metrics
│   └── overlays/
│       └── site-class/small/kustomization.yaml     Site-class overlay for small SNOs
│
└── platform/
    ├── placements/
    │   ├── all-hubs.yaml                           Placement: Global Hub targets managed hubs
    │   └── binding-managed-hubs.yaml               PlacementBinding for managed hub policies
    └── policies/
        ├── amq-broker-operator.yaml                OperatorPolicy source: AMQ Broker
        ├── enable-uwm.yaml                         OperatorPolicy source: UWM
        └── openshift-gitops-operator.yaml          OperatorPolicy source: GitOps
```

## Related Documentation

- [GitOps Flow Diagram](../docs/diagrams/gitops-flow.md) — sequence diagram of push and pull stages.
- [Mode 2 Container Diagram](../docs/diagrams/mode2-containers.md) — full Mode 2 architecture.
- [Architecture](../docs/architecture.md) — tier model, metrics, and messaging overlay.
