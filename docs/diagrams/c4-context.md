# System Context Diagram

The Artemis Edge ACM Demo is a Helm-based platform that deploys federated
AMQ Broker messaging across RHACM-managed Single Node OpenShift (SNO) edge
clusters. Three actor types interact with the system. External services
provide infrastructure, container images, and cluster provisioning.

```mermaid
flowchart TB
    PlatformEng["Platform Engineer
    Deploys and operates
    the demo environment"]

    Developer["Developer
    Modifies Helm chart,
    broker configs, Java clients"]

    DemoAttendee["Demo Attendee
    Follows Showroom lab guide,
    provisions SNOs, produces/consumes messages"]

    subgraph boundary ["Artemis Edge ACM Demo"]
        HelmChart["Helm Chart
        Templates for operators, brokers,
        security, policies, observability"]

        FleetGitOps["Fleet GitOps
        App-of-Apps for Mode 2
        push to hubs, pull to SNOs"]

        Showroom["Showroom Lab Guide
        Antora modules 0-8,
        terminal, RBAC"]

        Scripts["Lifecycle Scripts
        bootstrap, deploy, spokes,
        teardown, TLS generation"]

        JavaClients["Java Clients
        Quarkus Camel AMQP,
        MQTT, bridge"]
    end

    GCP["Google Cloud Platform
    Compute, DNS, storage
    for OpenShift clusters"]

    RHDP["RHDP / AgnosticD
    Provisions OpenShift clusters
    via execution environments"]

    RedHatReg["Red Hat Registries
    Operator catalogs,
    container images"]

    GitHub["GitHub
    Source repo, CI/CD,
    Pages for lab preview"]

    PlatformEng -->|"bootstrap, deploy,
    configure"| Scripts
    Developer -->|"modify chart,
    test locally"| HelmChart
    Developer -->|"build, run"| JavaClients
    DemoAttendee -->|"follow modules,
    provision SNOs"| Showroom

    Scripts -->|"agd provision /
    destroy"| RHDP
    Scripts -->|"gcloud auth,
    DNS zones"| GCP
    HelmChart -->|"pull operators,
    images"| RedHatReg
    FleetGitOps -->|"sync from
    repo branches"| GitHub
    RHDP -->|"create VMs,
    install OCP"| GCP
```

## Legend

| Element | Description |
|---------|-------------|
| **Platform Engineer** | Runs `bootstrap.sh` and `deploy.sh` to provision clusters and deploy workloads. |
| **Developer** | Edits Helm templates, values overlays, fleet-gitops configs, or Java clients. |
| **Demo Attendee** | Uses Showroom to walk through modules, provision SNO spokes, and test messaging. |
| **Helm Chart** | Single chart at repo root. Deploys operators, brokers, Keycloak, ACM policies, and observability. |
| **Fleet GitOps** | Mode 2 only. Argo CD Application that pushes config to regional hubs and pulls AMQ to SNOs. |
| **Showroom** | Antora lab guide with terminal access. Deployed on a hub cluster. |
| **RHDP / AgnosticD** | Red Hat Demo Platform provisioner. Creates OpenShift clusters on GCP. |
| **GCP** | Google Cloud Platform. Hosts all clusters in this demo. |
| **Red Hat Registries** | `registry.redhat.io` and `redhat-operators` catalog. Supplies operator bundles and images. |
| **GitHub** | Hosts the source repo, runs Helm lint CI, and publishes the Antora static preview. |
