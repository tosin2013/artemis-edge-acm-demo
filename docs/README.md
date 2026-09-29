# Documentation Index

Technical documentation for the Artemis Edge ACM Demo. This platform
deploys federated AMQ Broker messaging across RHACM-managed Single Node
OpenShift (SNO) edge clusters in two modes: single-hub (Mode 1) and
hub-of-hubs (Mode 2).

For the hands-on lab guide, use Showroom on the hub cluster or see the
[static preview](https://tosin2013.github.io/artemis-edge-acm-demo/).

---

## Guides

| Document | Audience | Description |
|----------|----------|-------------|
| [Platform Engineer Guide](platform-guide.md) | Platform engineers | Deploy, configure, operate, and troubleshoot the demo environment. |
| [Developer Guide](developer-guide.md) | Developers | Modify the Helm chart, add regions, change broker configs, build Java clients. |
| [GCP Deployment Guide](gcp-deployment.md) | Platform engineers | Step-by-step GCP deployment with AgnosticD v2, secrets setup, and troubleshooting. |

## Architecture

| Document | Description |
|----------|-------------|
| [Architecture](architecture.md) | Mode 2 tier model, ACM vs AMQ hub terminology, GitOps model, metrics strategy, messaging overlay (address classes 5603-5607). |
| [Mode 2 AgnosticD Audit](mode2-agnosticd-audit.md) | Static audit of the Mode 2 AgnosticD config refactor. |

## Diagrams

Mermaid diagrams that render in GitHub and any GFM-compatible viewer.

| Diagram | Type | Description |
|---------|------|-------------|
| [System Context](diagrams/c4-context.md) | C4 Context | Actors, system boundary, and external systems (GCP, RHDP, registries, GitHub). |
| [Mode 1 Containers](diagrams/mode1-containers.md) | C4 Container | Single ACM hub with Argo CD, hub broker, Keycloak, MCO/Grafana, and SNO edge sites. |
| [Mode 2 Containers](diagrams/mode2-containers.md) | C4 Container | Global Hub (Tier 0), three regional hubs (Tier 1), and SNO sites (Tier 2). |
| [GitOps Flow](diagrams/gitops-flow.md) | Sequence | Push from Global Hub to regionals, pull from regionals to SNOs, region tag promotion. |
| [Message Federation](diagrams/message-federation.md) | Sequence | Address classes 5603-5607 routing: site-local, site-to-hub, site-to-site, broadcast, targeted. |
| [Deployment Lifecycle](diagrams/deployment-lifecycle.md) | Flowchart | Bootstrap to deploy to spoke provisioning to teardown, with Mode 1 vs Mode 2 decision nodes. |
| [Helm Chart Components](diagrams/helm-components.md) | Flowchart | Template groups, sync-wave ordering (waves 0-6), and conditional rendering by values toggles. |

---

## Quick Links

- [Root README](../README.md) -- project overview, quick start, and repository structure.
- [Showroom Lab Guide](https://tosin2013.github.io/artemis-edge-acm-demo/) -- static preview of the hands-on modules.
- [fleet-gitops README](../fleet-gitops/README.md) -- Mode 2 App-of-Apps layout and region tag strategy.
- [CONTRIBUTING.md](../CONTRIBUTING.md) -- contributor guidelines and pull request workflow.
