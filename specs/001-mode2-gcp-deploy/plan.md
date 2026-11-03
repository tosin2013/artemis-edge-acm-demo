# Plan — 001 Mode 2 GCP Deploy

> PLAYBOOK-infra section 3: mechanism, sync order, commands per rung.

## Build mode

**Direct mode** (without a worker). The human runs deploy scripts from
`tasks.md`. The AI writes governance files and guides evidence collection.
No sandbox, no git bundle — the existing `bootstrap.sh` / `deploy.sh`
scripts are the implementation.

## Mechanism

| Layer | Tool | Source |
|-------|------|--------|
| Provisioning | AgnosticD v2 (`agd provision`) | `agnosticd/gcp/vars-multihub*.yml` |
| Cluster workloads | Helm chart (this repo, rendered by ArgoCD) | `values-mode2-global.yaml`, `values-mode2.yaml`, `values-gcp.yaml` |
| Multi-hub GitOps | fleet-gitops Kustomize overlays | `fleet-gitops/` |
| Hub import | Shell script | `scripts/import-managed-hubs.sh` |
| Lifecycle | Shell wrappers | `scripts/deploy.sh`, `teardown.sh`, `start.sh`, `stop.sh` |

## Deploy order

```
1. bootstrap.sh (prerequisites, AgnosticD setup, secrets, TLS)
2. agd provision: global-<SANDBOX>    (T0, us-east1)       ~50 min
3. agd provision: east-<SANDBOX>      (T1, us-east4)       ~50 min
4. agd provision: cen-<SANDBOX>       (T1, us-central1)    ~50 min
5. agd provision: west-<SANDBOX>      (T1, us-west1)       ~50 min
6. import-managed-hubs.sh             (finalize)           ~5 min
                                                    Total: ~3h 25min
```

T1 tiers can run in parallel after T0 is up (separate terminal sessions).

## Sync order (within each cluster)

AgnosticD workload execution order (set in vars):
1. cert-manager (ClusterIssuer + certificates)
2. htpasswd-auth (workshop users)
3. RHACM (MultiClusterHub)
4. OpenShift GitOps (ArgoCD)
5. Field Content (this Helm chart via ArgoCD Application)
6. Showroom (lab guide, east only in Mode 2)

ArgoCD sync waves within the Helm chart are supposed to install operators before custom resources. Discovery runs before those waves. `SkipDryRunOnMissingResource=true` does not skip it, so `field-content` stays OutOfSync until the Keycloak, AMQ, and MulticlusterGlobalHub CRDs exist. `scripts/post-provision-multihub.sh` step 2b (`scripts/prime-field-content.sh`) applies the chart's Namespace, OperatorGroup, and Subscription documents, waits for those API groups, and requests a sync. A hard refresh alone does not retry a failed sync of the same revision. That sync creates the `fleet-gitops` Application, which applies `fleet-gitops/applicationsets/hubs.yaml` and generates `hub-config-*`.

## Rung commands

### Rung 1 — Static (before any cluster work)

```bash
# Lint
helm lint .
helm lint . -f values-mode2.yaml
helm lint . -f values-mode2-global.yaml

# Template render
helm template test . -f values.yaml -f values-gcp.yaml \
  --set global.clusterDomain=ci-test.example.com \
  > docs/evidence/001-mode2-gcp-deploy/rung1/rendered-mode1.yaml

helm template test . -f values.yaml -f values-mode2.yaml -f values-gcp.yaml \
  --set global.clusterDomain=ci-test.example.com \
  > docs/evidence/001-mode2-gcp-deploy/rung1/rendered-regional.yaml

helm template test . -f values.yaml -f values-mode2-global.yaml -f values-gcp.yaml \
  --set global.clusterDomain=ci-test.example.com \
  > docs/evidence/001-mode2-gcp-deploy/rung1/rendered-global.yaml

# Negative checks: Global Hub must not render broker or Showroom
grep -c 'kind: ActiveMQArtemis' docs/evidence/001-mode2-gcp-deploy/rung1/rendered-global.yaml
# Expected: 0
grep -c 'kind: Showroom\|showroom' docs/evidence/001-mode2-gcp-deploy/rung1/rendered-global.yaml | head -5
# Expected: 0 relevant CRs
```

Save all output (stdout + exit codes) to `docs/evidence/001-mode2-gcp-deploy/rung1/`.

### Rung 2 — Dry-run

Not applicable for AgnosticD provisioning (no pre-existing cluster to
dry-run against). Note: after initial deployment, future Helm changes could
use `argocd app diff` or `kubectl diff` against the running clusters.

### Rung 3 — Reconcile (after deploy + finalize)

```bash
# On Global Hub
oc login <global-hub-api>
oc get applications -n openshift-gitops -o wide
oc get managedclusters -o wide
oc get multiclusterglobalhub -A

# On each regional hub
for hub in east central west; do
  oc login <${hub}-hub-api>
  oc get applications -n openshift-gitops -o wide
  oc get multiclusterhub -A
  oc get activemqartemis -A
done

# Second diff: re-check after 10 minutes, confirm no drift
```

Save to `docs/evidence/001-mode2-gcp-deploy/rung3/`.

### Rung 4 — Security (after rung 3)

```bash
# On each cluster: RBAC review
oc adm policy who-can create clusterrolebindings
oc get clusterrolebindings -o json | jq '.items[] | select(.roleRef.name=="cluster-admin") | .subjects'

# Pod security / SCC
oc get pods -A -o json | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name) \(.metadata.annotations["openshift.io/scc"] // "unknown")"'
```

Save to `docs/evidence/001-mode2-gcp-deploy/rung4/`.

### Rung 5 — Functional (after rung 3)

```bash
./scripts/validate-deployment.sh --mode multi-hub

# Manual smoke tests
# - Showroom route on east returns 200
# - ArgoCD console on Global Hub accessible
# - Grafana compliance dashboard on Global Hub loads
# - AMQ hub-01 console on each regional hub accessible
# - Keycloak admin console on each regional hub accessible
```

Save to `docs/evidence/001-mode2-gcp-deploy/rung5/`.

### Rung 6 — Teardown

```bash
# Capture before state
oc get all -A > docs/evidence/001-mode2-gcp-deploy/rung6/before-<tier>.txt
gcloud compute instances list --project=openenv-<SANDBOX> > docs/evidence/001-mode2-gcp-deploy/rung6/gcp-before.txt

# Destroy (reverse order)
./scripts/deploy.sh --mode multi-hub --tier west --sandbox <SANDBOX> --destroy
./scripts/deploy.sh --mode multi-hub --tier central --sandbox <SANDBOX> --destroy
./scripts/deploy.sh --mode multi-hub --tier east --sandbox <SANDBOX> --destroy
./scripts/deploy.sh --mode multi-hub --tier global --sandbox <SANDBOX> --destroy

# Capture after state
gcloud compute instances list --project=openenv-<SANDBOX> > docs/evidence/001-mode2-gcp-deploy/rung6/gcp-after.txt
gcloud compute disks list --project=openenv-<SANDBOX> >> docs/evidence/001-mode2-gcp-deploy/rung6/gcp-after.txt
```

Save to `docs/evidence/001-mode2-gcp-deploy/rung6/`.

## Pre-flight checks (added after first deploy failure)

Before any `agd provision`, verify:

```bash
# 1. Pull secret is populated (not a placeholder) in the secrets file
python3 -c "
import yaml, json
s = yaml.safe_load(open('$HOME/Development/agnosticd-v2-secrets/secrets-openenv-gcp.yml'))
ps = json.loads(s['ocp4_pull_secret'])
assert 'auths' in ps and len(ps['auths']) > 0, 'Pull secret is empty or invalid'
print(f'OK: pull secret has {len(ps[\"auths\"])} registry entries')
"

# 2. GCP key PEM is valid
python3 scripts/validate-gcp-key.py $HOME/Development/agnosticd-v2-secrets/gcp-key-<SANDBOX>.json

# 3. gcloud is authenticated
gcloud auth list --filter=status:ACTIVE --format='value(account)' | grep -q .

# 4. All bootstrap checks pass
./bootstrap.sh --check-only
```

## Recovery: stale bastion after a failed deploy

If `agd provision` fails during `openshift-install` (Step 004), the bastion
retains stale `install-config.yaml` and `.openshift_install.log` files without
an `auth/` directory. A re-provision will skip the install and fail reading
`kubeadmin-password`.

**Fix:** SSH to the bastion and remove the stale directory before retrying:

```bash
GUID="${tier}-<SANDBOX>"
SSH_KEY="$HOME/Development/agnosticd-v2-output/${GUID}/ssh_provision_${GUID}"
IP=$(grep 'Hostname' $HOME/Development/agnosticd-v2-output/${GUID}/openshift-cluster_${GUID}_ssh_conf | awk '{print $2}')
# cluster dir: hub (global), hub-east, hub-central, hub-west
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "gcp-user@${IP}" "rm -rf /home/gcp-user/<cluster-dir>"
```

Then re-run `deploy.sh` for that tier.

## Skills used (PLAYBOOK-infra section 7)

From [tosin2013/rhel-devops-skills-cli](https://github.com/tosin2013/rhel-devops-skills-cli):

```bash
git clone https://github.com/tosin2013/rhel-devops-skills-cli.git ~/rhel-devops-skills-cli
cd ~/rhel-devops-skills-cli
for skill in agnosticd agnosticd-deploy-test static-validation field-sourced-content onboard; do
  ./install.sh install --skill "$skill" --ide cursor
done
```

| Skill | Use in this spec |
|-------|-----------------|
| `agnosticd` | Plan, tasks, review — AgnosticD v2 vars, secrets wiring, `agd` CLI |
| `agnosticd-deploy-test` | Rungs 3, 5, 6 — end-to-end deploy validation, stale bastion detection |
| `static-validation` | Rung 1 — offline render, schema, policy, secrets scan, lint |
| `field-sourced-content` | Plan, tasks — RHDP Helm chart delivery pattern |
| `onboard` | Setup, repeatability check — reads `onboard.yml`, validates environment, catches bootstrap.sh bugs; runs the PLAYBOOK-infra repeatability check (deploy, teardown, redeploy on fresh targets) |

## Dependencies

- GCP OpenEnv sandbox (5-char ID) with `gcp-key.json`
- Pull secret from console.redhat.com — **must be injected into
  `agnosticd-v2-secrets/secrets-openenv-gcp.yml` as `ocp4_pull_secret`
  (valid JSON with `auths` key, not a placeholder)**
- GCP quotas: 132 N2 vCPUs + 4050 GiB SSD in each of 4 regions
- AgnosticD v2 clone with `agd setup` completed
- Java 21 + Maven for client builds (TLS generation needs `keytool`)
