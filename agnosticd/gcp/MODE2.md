# Mode 2 AgnosticD — four OpenShift clusters, zero SNOs

AgnosticD in this catalog provisions **one OpenShift cluster per GUID**.
Mode 2 is four provisions (four GUIDs), then you import the three regional
hubs into Global Hub. Do **not** list SNO ClusterDeployments in Helm.

| Order | Role | Vars file | Wrapper |
|-------|------|-----------|---------|
| 1 | Tier 0 Global Hub | `agnosticd/gcp/vars-multihub.yml` | `./scripts/deploy.sh --mode multi-hub --tier global --guid <GH_GUID>` |
| 2 | Tier 1 ACM east (student Showroom + AMQ hub) | `agnosticd/gcp/vars-multihub-regional.yml` | `./scripts/deploy.sh --mode multi-hub --tier regional --guid <EAST_GUID>` |
| 3 | Tier 1 ACM central | same regional file; set `gcp_region: us-central1`, `cluster_name: hub-central`, `global.region: central`, `showroom.enabled: false` | new GUID |
| 4 | Tier 1 ACM west | `gcp_region: us-west1`, `cluster_name: hub-west`, `global.region: west`, `showroom.enabled: false` | new GUID |

Copy vars into `agnosticd-v2-vars/` as:

- `artemis-edge-gcp-multihub.yml`
- `artemis-edge-gcp-multihub-regional.yml`

## After the four clusters are up

1. Import each regional hub into Global Hub as a managed hub.
2. Label them `hub-tier=regional` and `region=east|central|west`.
3. Apply `fleet-gitops/applicationsets/hubs.yaml` on Global Hub (Argo CD **push** of `hubs/<region>`).
4. Students log into **east**. Module 2 runs `deploy-spokes.sh` there. **Zero SNOs until that step.**
5. Global Hub inventory then lists the new site under that managed hub. Sites never talk to Global Hub.

## What each cluster runs

- **Global Hub:** Multicluster Global Hub operator, compliance Grafana (PostgreSQL), extra Thanos Query ConfigMap for fleet AMQ. **No AMQ broker. No Showroom.**
- **Regional hub:** full ACM, MCO/Thanos + regional GCS, one AMQ hub broker (`hub-01`), Showroom on east only.
- **SNOs:** student Module 2.

Do not use GUID `7d2ft` unless a human asks. Mode 1 remains frozen at tag `mode-1`.
