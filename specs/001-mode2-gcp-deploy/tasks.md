# Tasks — 001 Mode 2 GCP Deploy

> One task = one reconcilable unit. Each lists its rung-1 check.
> Direct mode: human executes all tasks.
>
> **Update 2026-10-29:** Added User Story 0 (pre-flight) and Task 2.3
> (stale bastion recovery) after the first deploy failed due to an empty
> pull secret and stale install artifacts on the bastions.

## User Story 0: Pre-flight checks (added after first failure)

### Task 0.1: Verify pull secret is wired

```bash
python3 -c "
import yaml, json
s = yaml.safe_load(open('$HOME/Development/agnosticd-v2-secrets/secrets-openenv-gcp.yml'))
ps = json.loads(s['ocp4_pull_secret'])
assert 'auths' in ps and len(ps['auths']) > 0, 'FAIL: pull secret empty or invalid'
print(f'PASS: pull secret has {len(ps[\"auths\"])} registry entries')
"
```

**Rung-1 check:** Prints `PASS` with >0 registry entries.

### Task 0.2: Verify GCP key PEM integrity

```bash
python3 scripts/validate-gcp-key.py \
  $HOME/Development/agnosticd-v2-secrets/gcp-key-<SANDBOX>.json
```

**Rung-1 check:** Exits 0, prints `OK`.

### Task 0.3: Clean stale bastion state (if retrying after a failed deploy)

```bash
for tier in global east cen west; do
  GUID="${tier}-<SANDBOX>"
  SSH_KEY="$HOME/Development/agnosticd-v2-output/${GUID}/ssh_provision_${GUID}"
  IP=$(grep 'Hostname' \
    $HOME/Development/agnosticd-v2-output/${GUID}/openshift-cluster_${GUID}_ssh_conf \
    | awk '{print $2}')
  CLUSTER_DIR=$(case $tier in
    global) echo hub;; east) echo hub-east;;
    cen) echo hub-central;; west) echo hub-west;; esac)
  echo "Cleaning ${tier} bastion (${IP})..."
  ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "gcp-user@${IP}" \
    "rm -rf /home/gcp-user/${CLUSTER_DIR}" 2>/dev/null \
    && echo "  OK" || echo "  SKIP (no bastion or no stale dir)"
done
```

**Rung-1 check:** N/A (recovery step). Only needed when retrying.

---

## User Story 1: Static validation (rung 1)

### Task 1.1: Helm lint all overlays

```bash
helm lint . 2>&1 | tee docs/evidence/001-mode2-gcp-deploy/rung1/lint-mode1.log
helm lint . -f values-mode2.yaml 2>&1 | tee docs/evidence/001-mode2-gcp-deploy/rung1/lint-regional.log
helm lint . -f values-mode2-global.yaml 2>&1 | tee docs/evidence/001-mode2-gcp-deploy/rung1/lint-global.log
```

**Rung-1 check:** All three exit 0 with no errors.

### Task 1.2: Helm template render all overlays

```bash
helm template test . -f values.yaml -f values-gcp.yaml \
  --set global.clusterDomain=ci-test.example.com \
  --set global.clusterApiUrl=https://api.ci-test.example.com:6443 \
  > docs/evidence/001-mode2-gcp-deploy/rung1/rendered-mode1.yaml 2>&1

helm template test . -f values.yaml -f values-mode2.yaml -f values-gcp.yaml \
  --set global.clusterDomain=ci-test.example.com \
  --set global.clusterApiUrl=https://api.ci-test.example.com:6443 \
  > docs/evidence/001-mode2-gcp-deploy/rung1/rendered-regional.yaml 2>&1

helm template test . -f values.yaml -f values-mode2-global.yaml -f values-gcp.yaml \
  --set global.clusterDomain=ci-test.example.com \
  --set global.clusterApiUrl=https://api.ci-test.example.com:6443 \
  > docs/evidence/001-mode2-gcp-deploy/rung1/rendered-global.yaml 2>&1
```

**Rung-1 check:** All three exit 0. Rendered YAML is valid.

### Task 1.3: Negative checks on Global Hub render

```bash
echo "--- Negative check: no ActiveMQArtemis in Global Hub render ---"
if grep -q 'kind: ActiveMQArtemis' docs/evidence/001-mode2-gcp-deploy/rung1/rendered-global.yaml; then
  echo "FAIL: Global Hub render contains ActiveMQArtemis"
  exit 1
else
  echo "PASS: No ActiveMQArtemis in Global Hub render"
fi

echo "--- Negative check: no Showroom deployment in Global Hub render ---"
if grep -q 'name: showroom' docs/evidence/001-mode2-gcp-deploy/rung1/rendered-global.yaml; then
  echo "FAIL: Global Hub render contains Showroom"
  exit 1
else
  echo "PASS: No Showroom in Global Hub render"
fi
```

**Rung-1 check:** Both negative checks PASS.

---

## User Story 2: Bootstrap and setup

### Task 2.1: Run bootstrap.sh

```bash
./bootstrap.sh
# Select: multi-hub mode
# Provide: GCP sandbox ID, accept defaults
```

**Rung-1 check:** `bootstrap.sh --check-only` exits 0 after setup.

### Task 2.2: Verify onboard.yml validation

```bash
./bootstrap.sh --check-only 2>&1 | tee docs/evidence/001-mode2-gcp-deploy/rung1/bootstrap-check.log
```

**Rung-1 check:** All validation checks pass (multi-hub vars, TLS, quotas).

---

## User Story 3: Provision Global Hub (T0)

### Task 3.1: Deploy T0

```bash
./scripts/deploy.sh --mode multi-hub --tier global --sandbox <SANDBOX>
```

**Rung-1 check:** N/A (live deploy). Rung-3 check after completion:
- `oc get clusterversion` shows Available=True
- `oc get multiclusterglobalhub -A` shows phase Running

---

## User Story 4: Provision East regional hub (T1)

### Task 4.1: Deploy T1 east

```bash
./scripts/deploy.sh --mode multi-hub --tier east --sandbox <SANDBOX>
```

**Rung-1 check:** N/A (live deploy). Rung-3 check after completion:
- `oc get multiclusterhub -A` shows Running
- `oc get activemqartemis -A` shows a broker

---

## User Story 5: Provision Central regional hub (T1)

### Task 5.1: Deploy T1 central

```bash
./scripts/deploy.sh --mode multi-hub --tier central --sandbox <SANDBOX>
```

**Rung-1 check:** N/A. Same rung-3 checks as Task 4.1.

---

## User Story 6: Provision West regional hub (T1)

### Task 6.1: Deploy T1 west

```bash
./scripts/deploy.sh --mode multi-hub --tier west --sandbox <SANDBOX>
```

**Rung-1 check:** N/A. Same rung-3 checks as Task 4.1.

---

## User Story 7: Finalize hub-of-hubs

### Task 7.1: Import regional hubs

```bash
./scripts/post-provision-multihub.sh --sandbox <SANDBOX>
```

`import-managed-hubs.sh` alone labels and joins the hubs. It does not make `field-content` sync. The finalize script's step 2b runs `prime-field-content.sh` first so the Keycloak, AMQ, and MulticlusterGlobalHub APIs exist before Argo CD refreshes the chart.

**Rung-1 check:** N/A. Rung-3 check:
- `oc get managedclusters` on Global Hub shows 3 clusters JOINED+AVAILABLE
- Labels `hub-tier=regional` and `region=east|central|west` present
- `fleet-gitops` ApplicationSet generated hub-config Apps

---

## User Story 8: Evidence collection — Rung 3 (reconcile)

### Task 8.1: Capture ArgoCD status on all clusters

```bash
mkdir -p docs/evidence/001-mode2-gcp-deploy/rung3

# Global Hub
oc login <global-api>
oc get applications -n openshift-gitops -o yaml \
  > docs/evidence/001-mode2-gcp-deploy/rung3/argocd-global.yaml
oc get managedclusters -o yaml \
  > docs/evidence/001-mode2-gcp-deploy/rung3/managedclusters.yaml
oc get multiclusterglobalhub -A -o yaml \
  > docs/evidence/001-mode2-gcp-deploy/rung3/globalhub-status.yaml

# Regional hubs
for hub in east cen west; do
  oc login <${hub}-api>
  oc get applications -n openshift-gitops -o yaml \
    > docs/evidence/001-mode2-gcp-deploy/rung3/argocd-${hub}.yaml
  oc get multiclusterhub -A -o yaml \
    > docs/evidence/001-mode2-gcp-deploy/rung3/acm-${hub}.yaml
  oc get activemqartemis -A -o yaml \
    > docs/evidence/001-mode2-gcp-deploy/rung3/amq-${hub}.yaml
done
```

### Task 8.2: Drift check (10 min later)

```bash
sleep 600
# Re-capture and diff
oc login <global-api>
oc get applications -n openshift-gitops -o yaml \
  > docs/evidence/001-mode2-gcp-deploy/rung3/argocd-global-t2.yaml
diff docs/evidence/001-mode2-gcp-deploy/rung3/argocd-global.yaml \
     docs/evidence/001-mode2-gcp-deploy/rung3/argocd-global-t2.yaml \
  > docs/evidence/001-mode2-gcp-deploy/rung3/drift-check.diff || true
```

**Rung-3 check:** All ArgoCD apps Synced/Healthy. Drift diff empty or
timestamps-only.

---

## User Story 9: Evidence collection — Rung 5 (functional)

### Task 9.1: Run validation script

```bash
mkdir -p docs/evidence/001-mode2-gcp-deploy/rung5
./scripts/validate-deployment.sh --mode multi-hub 2>&1 \
  | tee docs/evidence/001-mode2-gcp-deploy/rung5/validate.log
```

### Task 9.2: Smoke tests

```bash
# Showroom on east
curl -sk -o /dev/null -w "%{http_code}" https://showroom.<east-domain>/
# Expected: 200

# ArgoCD on Global Hub
curl -sk -o /dev/null -w "%{http_code}" https://openshift-gitops-server-openshift-gitops.<global-domain>/
# Expected: 200 or 302

# AMQ console on each regional hub
for hub_domain in <east-domain> <central-domain> <west-domain>; do
  curl -sk -o /dev/null -w "%{http_code}" https://artemis-hub-01-wconsj-0-svc-rte-artemis.${hub_domain}/
done
# Expected: 200 each
```

Save all output to `docs/evidence/001-mode2-gcp-deploy/rung5/smoke-tests.log`.

---

## User Story 10: Evidence collection — Rung 4 (security)

### Task 10.1: RBAC review

```bash
mkdir -p docs/evidence/001-mode2-gcp-deploy/rung4

for ctx in global east cen west; do
  oc login <${ctx}-api>
  echo "=== ${ctx}: cluster-admin bindings ===" >> docs/evidence/001-mode2-gcp-deploy/rung4/rbac.log
  oc get clusterrolebindings -o json \
    | jq '.items[] | select(.roleRef.name=="cluster-admin") | {name: .metadata.name, subjects: .subjects}' \
    >> docs/evidence/001-mode2-gcp-deploy/rung4/rbac.log
done
```

### Task 10.2: Pod security / SCC check

```bash
for ctx in global east cen west; do
  oc login <${ctx}-api>
  echo "=== ${ctx}: SCC per pod ===" >> docs/evidence/001-mode2-gcp-deploy/rung4/scc.log
  oc get pods -A -o json \
    | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name) \(.metadata.annotations["openshift.io/scc"] // "N/A")"' \
    >> docs/evidence/001-mode2-gcp-deploy/rung4/scc.log
done
```

---

## User Story 11: Evidence collection — Rung 6 (teardown)

### Task 11.1: Capture pre-teardown state

```bash
mkdir -p docs/evidence/001-mode2-gcp-deploy/rung6
gcloud compute instances list --project=openenv-<SANDBOX> \
  > docs/evidence/001-mode2-gcp-deploy/rung6/gcp-instances-before.txt
gcloud compute disks list --project=openenv-<SANDBOX> \
  > docs/evidence/001-mode2-gcp-deploy/rung6/gcp-disks-before.txt
```

### Task 11.2: Destroy all tiers

```bash
./scripts/deploy.sh --mode multi-hub --tier west --sandbox <SANDBOX> --destroy
./scripts/deploy.sh --mode multi-hub --tier central --sandbox <SANDBOX> --destroy
./scripts/deploy.sh --mode multi-hub --tier east --sandbox <SANDBOX> --destroy
./scripts/deploy.sh --mode multi-hub --tier global --sandbox <SANDBOX> --destroy
```

### Task 11.3: Capture post-teardown state

```bash
gcloud compute instances list --project=openenv-<SANDBOX> \
  > docs/evidence/001-mode2-gcp-deploy/rung6/gcp-instances-after.txt
gcloud compute disks list --project=openenv-<SANDBOX> \
  > docs/evidence/001-mode2-gcp-deploy/rung6/gcp-disks-after.txt
gcloud dns managed-zones list --project=openenv-<SANDBOX> \
  > docs/evidence/001-mode2-gcp-deploy/rung6/gcp-dns-after.txt
```

**Rung-6 check:** After lists show no cluster VMs, no orphaned disks, no
leftover DNS zones beyond the sandbox default.

---

## User Story 12: Install rhel-devops-skills-cli skills

### Task 12.1: Clone and install selected skills

```bash
git clone https://github.com/tosin2013/rhel-devops-skills-cli.git ~/rhel-devops-skills-cli
cd ~/rhel-devops-skills-cli
for skill in agnosticd agnosticd-deploy-test static-validation field-sourced-content onboard; do
  ./install.sh install --skill "$skill" --ide cursor
done
./install.sh verify --all
```

**Check:** `./install.sh list` shows all 5 skills installed.

### Task 12.2: Run onboard skill repeatability check

After rung 6 (teardown), use the `onboard` skill to drive the PLAYBOOK-infra
repeatability check on a fresh disposable cluster:

1. Clone the repo on a fresh machine (or clean checkout)
2. Run `bootstrap.sh` with defaults (reads `onboard.yml`)
3. Deploy, capture rung 3 + 5 evidence
4. Tear down (rung 6), then deploy again
5. Compare the two runs: same Synced/Healthy state, same test results

Save artifacts to `docs/evidence/001-mode2-gcp-deploy/repeat/`.

**Repeatability check:** Two consecutive deploy/teardown cycles produce
identical rung 3 and rung 5 evidence. Any hand step required is a bug
to add to `onboard.yml` or `bootstrap.sh`.
