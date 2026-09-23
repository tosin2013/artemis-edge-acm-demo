# Mode 2 AgnosticD — four OpenShift clusters, one OpenEnv, zero SNOs

RHDP catalog items are **one catalog item** and **one GUID** (one OpenShift cluster). This repo does not wrap Mode 2 into a single catalog SKU. Operators run four `agd provision`s in **one** OpenEnv project. Do **not** collapse T0 and T1 into one cluster. Do **not** list SNO ClusterDeployments in Helm.

`generate-secrets.sh` takes the **sandbox** id only (`abc12` → `openenv-abc12` and `abc12.gcp.redhatworkshops.io`). Do not pass a composed agd GUID to it.

`scripts/deploy.sh --mode multi-hub` composes the AgnosticD GUID so `output_dir` and `bastion-{{ guid }}` do not collide. Hostname is `bastion-{{ guid }}.{{ guid }}.{{ base_domain }}` (systemd max 64 characters). **`hub-{tier}-{sandbox}` is too long** (`hub-global-<SANDBOX>` and `hub-east-<SANDBOX>` failed). Use `{region}-{sandbox}`. Central is **`cen`**, not `central` (`central-<SANDBOX>` is 65 characters).

`AGD_GUID={region}-{sandbox}`

MCO/Thanos on each hub is workload `ocp4_workload_rhacm_observability_gcs`. That role is not vendored here; AgnosticD v2 loads it from `ansible/roles/ocp4_workload_rhacm_observability_gcs` next to `bin/agd` (this host: `~/Development/agnosticd-v2/ansible/roles/ocp4_workload_rhacm_observability_gcs`).

| Order | Role | Vars file | Wrapper |
|-------|------|-----------|---------|
| 1 | Tier 0 Global Hub | `agnosticd/gcp/vars-multihub.yml` | `./scripts/deploy.sh --mode multi-hub --tier global --sandbox <SANDBOX>` → `global-<SANDBOX>` |
| 2 | Tier 1 ACM east (student Showroom + AMQ hub) | `agnosticd/gcp/vars-multihub-regional.yml` | `./scripts/deploy.sh --mode multi-hub --tier east --sandbox <SANDBOX>` → `east-<SANDBOX>` |
| 3 | Tier 1 ACM central | `agnosticd/gcp/vars-multihub-central.yml` | `./scripts/deploy.sh --mode multi-hub --tier central --sandbox <SANDBOX>` → `cen-<SANDBOX>` |
| 4 | Tier 1 ACM west | `agnosticd/gcp/vars-multihub-west.yml` | `./scripts/deploy.sh --mode multi-hub --tier west --sandbox <SANDBOX>` → `west-<SANDBOX>` |

`--tier regional` aliases `east`. `--guid <SANDBOX>` is accepted as the sandbox if `--sandbox` is omitted.

Copy vars into `agnosticd-v2-vars/` as:

- `artemis-edge-gcp-multihub.yml`
- `artemis-edge-gcp-multihub-regional.yml`
- `artemis-edge-gcp-multihub-central.yml`
- `artemis-edge-gcp-multihub-west.yml`

Shared from secrets (sandbox only): `gcp_project_id: openenv-<SANDBOX>`, `base_domain: <SANDBOX>.gcp.redhatworkshops.io`. Cluster APIs are `api.hub.<SANDBOX>.gcp.redhatworkshops.io`, `api.hub-east.<SANDBOX>.gcp.redhatworkshops.io`, and siblings.

## After the four clusters are up

Run the import script to register regional hubs with the Global Hub:

```bash
./scripts/import-managed-hubs.sh --sandbox <SANDBOX>
```

The script performs steps 1–3 automatically:

1. **Import** each regional hub into Global Hub as a `ManagedCluster` with an `auto-import-secret`.
2. **Label** them `hub-tier=regional` and `region=east|central|west`.
3. **Verify** all hubs reach `JOINED=True` and `AVAILABLE=True`.

The `fleet-gitops/applicationsets/hubs.yaml` ApplicationSet (deployed by `ocp4_workload_field_content` during provision) automatically generates `hub-config-*` ArgoCD Applications for each cluster with the `hub-tier: regional` label. No manual `oc apply` is needed.

4. Students log into **east**. Module 2 runs `deploy-spokes.sh` there. **Zero SNOs until that step.**
5. Global Hub inventory then lists the new site under that managed hub. Sites never talk to Global Hub.

## ArgoCD sizing for multi-hub

The Global Hub's ArgoCD `application-controller` scans regional clusters through the ACM cluster-proxy. With 4+ clusters, the default 2Gi memory limit causes OOMKill. The vars file sets `ocp4_workload_openshift_gitops_controller_limits_memory: 4Gi` to handle this. If adding more regional hubs, increase proportionally.

## What each cluster runs

- **Global Hub:** Multicluster Global Hub operator, compliance Grafana (PostgreSQL), extra Thanos Query ConfigMap for fleet AMQ. **No AMQ broker. No Showroom.**
- **Regional hub:** full ACM, MCO/Thanos + regional GCS, one AMQ hub broker (`hub-01`), Showroom on east only.
- **SNOs:** student Module 2.

Do not use GUID `7d2ft` unless a human asks. Mode 1 remains frozen at tag `mode-1`.
