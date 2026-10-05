# Mode 2 Quickstart — Hub-of-Hubs Deployment

Deploy the Artemis Edge ACM Demo in **Mode 2** (multi-hub): one Global Hub
plus three regional ACM hubs, each with its own AMQ hub broker.

## What Gets Created

```
                    Global Hub (Tier 0, us-east1)
                    ├─ ACM Global Hub operator
                    ├─ ArgoCD + fleet-gitops Application
                    ├─ Thanos Query (fleet AMQ metrics)
                    └─ NO AMQ brokers
                           |
              ArgoCD push  |  GH agent (outbound)
              +------------+------------+
              |            |            |
         ACM east       ACM central    ACM west        (Tier 1)
         us-east4       us-central1    us-west1
         hub-01 AMQ     hub-01 AMQ     hub-01 AMQ
         Keycloak       Keycloak       Keycloak
         Showroom       Showroom       Showroom
              |            |            |
           SNOs         SNOs          SNOs              (Tier 2, student)
           site AMQ     site AMQ      site AMQ
```

**4 clusters** are provisioned by AgnosticD. SNOs are created later by
students in Module 2.

## Prerequisites

Everything in the [main README](../README.md#quick-start) plus:

| Requirement | Details |
|---|---|
| GCP sandbox | A 5-character OpenEnv sandbox ID (e.g. `m28l2`) |
| GCP quotas | **132 N2 vCPUs + 4050 GiB SSD** in each of 4 regions |
| Pull secret | A real pull secret from [console.redhat.com](https://console.redhat.com/openshift/install/pull-secret) |
| Time | ~3-4 hours total (~50 min per tier) |

### GCP Quota Requirements

| Region | Tier | N2 vCPUs | SSD GiB |
|--------|------|----------|---------|
| us-east1 | Global Hub | 132 | 4050 |
| us-east4 | East regional | 132 | 4050 |
| us-central1 | Central regional | 132 | 4050 |
| us-west1 | West regional | 132 | 4050 |

Check quotas:
```bash
for region in us-east1 us-east4 us-central1 us-west1; do
  echo "=== $region ==="
  gcloud compute regions describe $region --project=openenv-<SANDBOX> \
    --format='json(quotas)' | python3 -c "
import json,sys
qs = json.load(sys.stdin).get('quotas', [])
for m in ['N2_CPUS', 'SSD_TOTAL_GB']:
    q = next((q for q in qs if q['metric'] == m), {})
    print(f\"  {m}: {int(q.get('usage',0))}/{int(q.get('limit',0))}\")
"
done
```

## One-Command Deploy

```bash
git clone https://github.com/tosin2013/artemis-edge-acm-demo.git
cd artemis-edge-acm-demo
cp ~/Downloads/gcp-key.json .
./bootstrap.sh
```

When prompted:
- **Deployment mode:** select `multi-hub`
- **GCP sandbox ID:** the bootstrap auto-detects it from `gcp-key.json`
- **Other prompts:** accept defaults or customize

The bootstrap script will:
1. Install all prerequisites
2. Clone AgnosticD and run setup
3. **Auto-patch** AgnosticD for RHDP Open Environment compatibility
4. Generate secrets and TLS certificates
5. Validate quotas in all 4 GCP regions
6. **Provision all 4 tiers sequentially** (global → east → central → west)
7. Auto-finalize: import regional hubs into Global Hub

### Non-Interactive

```bash
# Edit config.yml first (or run bootstrap.sh --reconfigure)
./bootstrap.sh --deploy
```

## Manual Tier-by-Tier Deploy

If you prefer to provision one tier at a time (e.g., to parallelize):

```bash
# Tier 0: Global Hub (us-east1) — deploy first
./scripts/deploy.sh --mode multi-hub --tier global --sandbox <SANDBOX>

# Tier 1: Regional hubs (can run in parallel after Global Hub is up)
./scripts/deploy.sh --mode multi-hub --tier east --sandbox <SANDBOX>
./scripts/deploy.sh --mode multi-hub --tier central --sandbox <SANDBOX>
./scripts/deploy.sh --mode multi-hub --tier west --sandbox <SANDBOX>

# Finalize (auto-runs after last tier, or run manually)
./scripts/deploy.sh --mode multi-hub --finalize --sandbox <SANDBOX>
```

## Time Estimates

| Tier | Duration | Cumulative |
|------|----------|------------|
| Global Hub | ~50 min | ~50 min |
| East regional | ~50 min | ~1h 40min |
| Central regional | ~50 min | ~2h 30min |
| West regional | ~50 min | ~3h 20min |
| Finalize | ~5 min | ~3h 25min |

## Monitoring Progress

Each tier provisions via `agd provision` which streams Ansible output.
Key milestones to watch for:

1. **Step 001** — GCP infrastructure (bastion VM) — ~5 min
2. **Step 004** — OpenShift install — ~30 min
3. **Step 005** — Workloads (RHACM, ArgoCD, Helm chart) — ~15 min

## Common Failures and Recovery

### cert-manager DNS zone mismatch

**Symptom:** Provision fails at cert-manager with "no matching DNS zone".

**Why:** cert-manager template hardcodes `dns-zone-{{ guid }}`, but the GCP
zone is `dns-zone-<sandbox>`. When guid is `east-m28l2`, the template
produces `dns-zone-east-m28l2` (wrong).

**Recovery:** `deploy.sh` auto-detects the mismatch after the first failure,
patches the ClusterIssuer, creates certificates with the correct DNS zone,
waits for them to become Ready (~30-90s), and retries provision. The retry
succeeds because the cert-manager workload finds existing Ready certs.
No manual intervention needed.

### Quota exceeded

**Symptom:** `QUOTA_EXCEEDED` error during GCP infrastructure creation.

**Recovery:** Request quota increases in the GCP console for the failed
region, wait for approval (~5 min), then re-run the failed tier.

### Pull secret invalid

**Symptom:** OpenShift install fails during bootstrap with auth errors.

**Recovery:** Get a fresh pull secret from
[console.redhat.com/openshift/install/pull-secret](https://console.redhat.com/openshift/install/pull-secret),
update `agnosticd-v2-secrets/secrets-openenv-gcp.yml`, and re-run.

### svc-acct-creds.json not found

**Symptom:** `host-ocp4-provisioner` fails looking for `svc-acct-creds.json`.

**Recovery:** The bootstrap script should have auto-patched AgnosticD. If not:
```bash
./scripts/patch-agnosticd-pre-infra.sh ~/Development/agnosticd-v2
```

## Validation

After all 4 tiers are up:

```bash
./scripts/validate-deployment.sh --mode multi-hub
```

## Destroy

```bash
# Destroy all 4 tiers
./scripts/deploy.sh --mode multi-hub --tier all --sandbox <SANDBOX> --action destroy
```

Or one at a time (reverse order):
```bash
./scripts/deploy.sh --mode multi-hub --tier west --sandbox <SANDBOX> --destroy
./scripts/deploy.sh --mode multi-hub --tier central --sandbox <SANDBOX> --destroy
./scripts/deploy.sh --mode multi-hub --tier east --sandbox <SANDBOX> --destroy
./scripts/deploy.sh --mode multi-hub --tier global --sandbox <SANDBOX> --destroy
```

## Switching from Mode 1

If you already have a Mode 1 deployment and want to switch:

```bash
# 1. Destroy the Mode 1 cluster
./scripts/deploy.sh --destroy --guid <OLD_GUID>

# 2. Reconfigure for Mode 2
./bootstrap.sh --reconfigure
# Select "multi-hub" when prompted

# 3. Deploy Mode 2
./bootstrap.sh --deploy
```

## Related Docs

- [Architecture](architecture.md) — tier model, GitOps flow, messaging overlay
- [Delivery Mechanisms](delivery-mechanisms.md) — how AMQ is deployed in each mode
- [GCP Deployment](gcp-deployment.md) — GCP-specific setup and troubleshooting
