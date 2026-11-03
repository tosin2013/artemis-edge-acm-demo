# VERIFY

> PLAYBOOK-infra verification checklist. Tick each box when its artifact exists
> in `docs/evidence/<spec>/`. A rung counts only with its artifact.

## Spec: 001-mode2-gcp-deploy

**Cluster/version:** OpenShift 4.22 on GCP OpenEnv `openenv-26j7t`
**Tool versions:** Helm v4.3.1, oc 4.22.18, agd (agnosticd-v2), ArgoCD ___
**Sandbox:** `26j7t` | **Intended regions:** us-east1, us-east4, us-central1, us-west1.
**Observed:** all 4 cluster infrastructures report `us-east1`.

### Evidence ladder

- [x] **Rung 1 static:** `helm lint` (3 overlays) + `helm template` (3 renders) exit 0.
      Negative checks: Global Hub render has no ActiveMQArtemis, no Showroom.
      `bootstrap.sh --check-only` passes (13/13 required, 8/8 quota).
      Artifacts: `docs/evidence/001-mode2-gcp-deploy/rung1/`

- [x] **Rung 2 dry-run:** N/A for initial provisioning (no pre-existing cluster).
      See `docs/evidence/001-mode2-gcp-deploy/rung2/README.md`.

- [ ] **Rung 3 reconcile:** All ArgoCD apps Synced/Healthy on all 4 clusters.
      3 ManagedClusters JOINED+AVAILABLE on Global Hub.
      Global Hub operator phase=Running.
      Drift check (10 min diff) empty or timestamps-only.
      Artifacts: `docs/evidence/001-mode2-gcp-deploy/rung3/`
      **Status:** Partial, 2026-10-30. `field-content`, `fleet-gitops`, and
      `hub-config-{east,cen,west}` are Synced/Healthy. ManagedClusters
      east/cen/west are JOINED and AVAILABLE. `multiclusterglobalhub` is
      Running. Regional MultiClusterHub is still Pending (hypershift-addon
      lease). `hub-01-broker` pods are Running but the CR is not Ready
      (broker.properties projection delay). Drift check not taken.

- [ ] **Rung 4 security:** RBAC diff reviewed (cluster-admin bindings listed).
      Pod security/SCC per workload documented.
      No unexpected cluster-admin bindings beyond defaults.
      Artifacts: `docs/evidence/001-mode2-gcp-deploy/rung4/` (`rbac.log`, `scc.log`).
      **Status:** Captured 2026-10-30. Human review of the bindings is still open.

- [ ] **Rung 5 functional:** `validate-deployment.sh --mode multi-hub` passes.
      Smoke tests: Showroom 200, ArgoCD console accessible, AMQ consoles 200,
      Keycloak consoles accessible, Grafana compliance dashboard loads.
      Artifacts: `docs/evidence/001-mode2-gcp-deploy/rung5/`
      **Status:** Argo CD console returns HTTP 200 on all 4 hubs. Validate is
      14/15 on the Global Hub (no hub-01 broker there) and 15/16 on each
      regional hub (MultiClusterHub not Running). Keycloak operator check
      matches `rhbk-operator`.

- [x] **Rung 6 teardown:** All 4 tiers destroyed (reverse order).
      GCP instances/disks before vs after: nothing left.
      No orphaned DNS zones beyond sandbox default.
      Artifacts: `docs/evidence/001-mode2-gcp-deploy/rung6/`
      **Status:** 2026-10-30. `deploy.sh --destroy` exited 0 but the GCP
      Ansible lookup returned no instances, so it did not delete them.
      `openshift-install destroy cluster` on each bastion removed the
      clusters; bastions and AgnosticD networks were then deleted.
      After snapshot: 0 instances, 0 disks, 0 networks. Zone
      `dns-zone-26j7t` remains.

### Pre-flight checks (added after deploy failure)

- [x] Pull secret is valid JSON with `auths` key in `secrets-openenv-gcp.yml`
- [x] GCP key PEM integrity validated
- [x] gcloud authenticated to `openenv-26j7t`
- [x] All bootstrap validation checks pass (13/13 + 8/8 quota)
- [x] Stale bastion install directories cleaned before re-provision

### Process checks

- [ ] `onboard.yml` updated if setup changed; repeatability check run if required
- [x] Bugs B1-B5 from ROADMAP.md addressed or tracked
- [ ] No secrets in diff; no new cluster-admin; rollback documented in spec
- [ ] Reviewed by: ___ (not the worker)
- [ ] Merged by: ___ (human)
