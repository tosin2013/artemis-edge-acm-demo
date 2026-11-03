# Spec 001 — Mode 2 GCP Deploy

> PLAYBOOK-infra section 3: desired cluster state + evidence per requirement.

## Goal

Deploy the Artemis Edge ACM Demo in Mode 2 (multi-hub) to a GCP OpenEnv
sandbox. Four OpenShift clusters, zero SNOs. Prove it works, prove it tears
down cleanly.

## Scope

- **Clusters:** 4 OpenShift clusters on GCP, one OpenEnv project
- **Cloud:** GCP only
- **Mode:** multi-hub (Mode 2)
- **SNOs:** out of scope (student Module 2)

## Desired state

### DS-1: Global Hub cluster (Tier 0, us-east1)

| Requirement | Required rung |
|-------------|---------------|
| OpenShift installed and healthy | 3 |
| Multicluster Global Hub operator installed and running | 3 |
| ArgoCD deployed, fleet-gitops Application Synced/Healthy | 3 |
| Thanos Query ConfigMap for fleet AMQ metrics present | 3 |
| Compliance Grafana (PostgreSQL) running | 5 |
| No AMQ broker deployed | 1 (negative: template must not render broker resources) |
| No Showroom deployed | 1 (negative: template must not render Showroom) |

### DS-2: Regional hub clusters (Tier 1, east/central/west)

| Requirement | Required rung |
|-------------|---------------|
| OpenShift installed and healthy (3 clusters) | 3 |
| RHACM installed on each | 3 |
| MCO/Thanos with regional GCS bucket on each | 3 |
| AMQ Broker Operator subscription on each | 3 |
| AMQ hub broker (hub-01) Healthy on each | 5 |
| Keycloak deployed and OIDC functional on each | 5 |
| Showroom deployed on east | 5 |
| ArgoCD deployed, fleet-gitops pull ApplicationSet present | 3 |
| Edge-broker-policies ready for SNO provisioning | 3 |

### DS-3: Hub-of-hubs integration

| Requirement | Required rung |
|-------------|---------------|
| All 3 regional hubs imported as ManagedClusters on Global Hub | 3 |
| Labels: `hub-tier=regional`, `region=east\|central\|west` | 3 |
| ManagedCluster status: JOINED=True, AVAILABLE=True | 3 |
| fleet-gitops ApplicationSet auto-generated hub-config Apps | 3 |
| Global Hub compliance status shows all regional policies | 5 |

### DS-4: Teardown

| Requirement | Required rung |
|-------------|---------------|
| All 4 clusters destroyed cleanly | 6 |
| No GCP resources left behind (VMs, disks, networks, DNS zones) | 6 |
| No orphaned ACM placements or ArgoCD apps | 6 |

## Out of scope

- SNO provisioning (student Module 2)
- Azure deployment
- Cross-region AMQ federation (hub-to-hub)
- CI/CD pipeline changes (future spec)
- `kubeconform`/`gitleaks` integration (future spec per ROADMAP.md)

## Forbidden changes

- No changes to cluster-scoped RBAC beyond what the chart already declares
- No new `cluster-admin` bindings
- No secrets committed to git
- No manual `oc apply` steps that are not also in git

## Known risks (discovered during first deploy attempt)

| Risk | Symptom | Mitigation |
|------|---------|------------|
| Pull secret not wired into AgnosticD secrets | `openshift-install` fails: `pullSecret: Invalid value: "<Add Your Pull Secret here>"` | Verify `ocp4_pull_secret` contains valid JSON with `auths` key before any `agd provision` |
| Stale bastion from a failed run | Re-provision skips `openshift-install`, then fails reading `kubeadmin-password` from missing `auth/` dir | SSH to bastion, remove the stale install directory (`/home/gcp-user/hub*`), then re-run |
| `bootstrap.sh` `cd` leak between setup steps | Vars sync step fails because `agd setup` changed the cwd | Run bootstrap with `--non-interactive` after manually completing setup steps, or fix the eval-in-subshell bug |
| Argo CD discovers CRDs before sync waves | `field-content` stays OutOfSync / Missing: `k8s.keycloak.org/v2alpha1`, `broker.amq.io/v1beta1`, or `operator.open-cluster-management.io/v1alpha4` is not served. `SkipDryRunOnMissingResource` does not skip discovery, so `fleet-gitops` and `hub-config-*` never appear | `post-provision-multihub.sh` step 2b runs `prime-field-content.sh`, which applies the chart's Namespace, OperatorGroup, and Subscription documents from the live Helm values, then requests a sync of the Application |

## Rollback

Revert = `agd destroy` for each tier (reverse order: west, central, east,
global). GitOps ensures no drift between git and cluster state. If a single
tier fails mid-provision, **clean the bastion install directory first**, then
re-run that tier's `agd provision`.

## Clarify answers (section 3 questions)

| Question | Answer |
|----------|--------|
| Which cluster(s) and versions? | 4 GCP clusters, OpenShift 4.22 |
| Who owns the namespace? | AgnosticD creates all namespaces via workloads |
| What is the rollback? | `agd destroy` per tier, reverse order |
| Which rung before merge vs before production? | Rung 1 before any cluster work; rungs 3+5 before calling it deployed; rung 6 at end of lifecycle |
| Where do secrets come from? | `generate-secrets.sh` + `generate-tls.sh`, stored in `agnosticd-v2-secrets/` outside repo |
| What is the teardown cost/TTL limit? | GCP compute cost ~$35/hr for 4 clusters; TTL = OpenEnv sandbox expiry |
