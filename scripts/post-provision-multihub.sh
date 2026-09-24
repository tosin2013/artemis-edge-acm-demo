#!/usr/bin/env bash
set -euo pipefail
#
# Post-Provision Finalize for Mode 2 (Multi-Hub)
#
# Runs automatically after the last tier provisions, or manually via:
#   ./scripts/post-provision-multihub.sh --sandbox <SANDBOX_ID>
#
# What it does:
#   1. Patches ClusterIssuer DNS zone on all 4 clusters (workaround for
#      core_workloads cert-manager role hardcoding dns-zone-{{ guid }})
#   2. Adds SkipDryRunOnMissingResource=true to ArgoCD Applications
#      (workaround for field_content role hardcoding syncOptions)
#   3. Imports regional hubs into the Global Hub as ManagedClusters
#
# Prerequisites:
#   - All 4 Mode 2 clusters provisioned (global + 3 regional)
#   - oc CLI available

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${AGD_OUTPUT_DIR:-${HOME}/Development/agnosticd-v2-output}"
SANDBOX=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sandbox)     SANDBOX="$2"; shift 2 ;;
    --output-dir)  OUTPUT_DIR="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 --sandbox <SANDBOX_ID> [--output-dir DIR]"
      echo ""
      echo "Post-provision finalize for Mode 2 multi-hub deployments."
      echo "Patches known upstream workarounds and imports regional hubs."
      exit 0
      ;;
    *) echo "ERROR: Unknown option '$1'" >&2; exit 1 ;;
  esac
done

if [[ -z "$SANDBOX" ]]; then
  echo "ERROR: --sandbox is required." >&2
  exit 1
fi

echo "=== Mode 2 Post-Provision Finalize — Sandbox: ${SANDBOX} ==="
echo ""

# ---------------------------------------------------------------------------
# Discover clusters
# ---------------------------------------------------------------------------
TIERS=(global east cen west)
TIER_TOKENS=(global east cen west)
declare -A KUBECONFIGS

for i in "${!TIERS[@]}"; do
  token="${TIER_TOKENS[$i]}"
  dir="${OUTPUT_DIR}/${token}-${SANDBOX}"
  kc="${dir}/openshift-cluster_${token}-${SANDBOX}_kubeconfig"
  if [[ -f "$kc" ]]; then
    KUBECONFIGS["${token}-${SANDBOX}"]="$kc"
  fi
done

echo "Found ${#KUBECONFIGS[@]} cluster(s)."
if [[ ${#KUBECONFIGS[@]} -lt 4 ]]; then
  echo "WARN: Expected 4 clusters but found ${#KUBECONFIGS[@]}. Some steps may be skipped." >&2
fi
echo ""

# ---------------------------------------------------------------------------
# Step 1: Patch ClusterIssuer DNS zone names
# ---------------------------------------------------------------------------
# The cert-manager role in core_workloads hardcodes:
#   hostedZoneName: dns-zone-{{ guid }}
# In Mode 2, guid is "{tier}-{sandbox}" but the GCP DNS zone is
# "dns-zone-{sandbox}". Patch to the correct zone name.
# ---------------------------------------------------------------------------
echo "--- Step 1: Patch ClusterIssuer DNS zone ---"

for hub_id in "${!KUBECONFIGS[@]}"; do
  kc="${KUBECONFIGS[$hub_id]}"
  current_zone=$(KUBECONFIG="$kc" oc get clusterissuer letsencrypt-production-gcp \
    -o jsonpath='{.spec.acme.solvers[0].dns01.cloudDNS.hostedZoneName}' 2>/dev/null || true)

  if [[ -z "$current_zone" ]]; then
    echo "  [SKIP] ${hub_id}: No ClusterIssuer found"
    continue
  fi

  correct_zone="dns-zone-${SANDBOX}"
  if [[ "$current_zone" == "$correct_zone" ]]; then
    echo "  [OK]   ${hub_id}: Already correct (${correct_zone})"
  else
    KUBECONFIG="$kc" oc patch clusterissuer letsencrypt-production-gcp --type=json \
      -p "[{\"op\":\"replace\",\"path\":\"/spec/acme/solvers/0/dns01/cloudDNS/hostedZoneName\",\"value\":\"${correct_zone}\"}]" \
      >/dev/null 2>&1
    echo "  [FIX]  ${hub_id}: ${current_zone} → ${correct_zone}"
  fi
done
echo ""

# ---------------------------------------------------------------------------
# Step 2: Patch ArgoCD Application syncOptions
# ---------------------------------------------------------------------------
# The field_content role hardcodes syncOptions: [CreateNamespace=true]
# and ignores ocp4_workload_field_content_sync_options. We need
# SkipDryRunOnMissingResource=true for CRD ordering.
# ---------------------------------------------------------------------------
echo "--- Step 2: Patch ArgoCD syncOptions ---"

for hub_id in "${!KUBECONFIGS[@]}"; do
  kc="${KUBECONFIGS[$hub_id]}"

  app_exists=$(KUBECONFIG="$kc" oc get applications.argoproj.io field-content \
    -n openshift-gitops --no-headers 2>/dev/null | wc -l)
  if [[ "$app_exists" -eq 0 ]]; then
    echo "  [SKIP] ${hub_id}: No field-content Application"
    continue
  fi

  current_opts=$(KUBECONFIG="$kc" oc get applications.argoproj.io field-content \
    -n openshift-gitops -o jsonpath='{.spec.syncPolicy.syncOptions}' 2>/dev/null)

  if echo "$current_opts" | grep -q "SkipDryRunOnMissingResource=true"; then
    echo "  [OK]   ${hub_id}: SkipDryRunOnMissingResource already set"
  else
    KUBECONFIG="$kc" oc patch applications.argoproj.io field-content -n openshift-gitops --type=json \
      -p '[{"op":"replace","path":"/spec/syncPolicy/syncOptions","value":["CreateNamespace=true","SkipDryRunOnMissingResource=true"]}]' \
      >/dev/null 2>&1
    echo "  [FIX]  ${hub_id}: Added SkipDryRunOnMissingResource=true"

    # Enable selfHeal and retry for reliable convergence
    KUBECONFIG="$kc" oc patch applications.argoproj.io field-content -n openshift-gitops --type=merge \
      -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":true},"retry":{"limit":10,"backoff":{"duration":"5s","factor":2,"maxDuration":"3m"}}}}}' \
      >/dev/null 2>&1

    # Trigger a fresh sync
    KUBECONFIG="$kc" oc annotate applications.argoproj.io field-content -n openshift-gitops \
      argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1
  fi
done
echo ""

# ---------------------------------------------------------------------------
# Step 3: Import regional hubs into the Global Hub
# ---------------------------------------------------------------------------
echo "--- Step 3: Import regional hubs ---"
"${SCRIPT_DIR}/import-managed-hubs.sh" --sandbox "${SANDBOX}" --output-dir "${OUTPUT_DIR}"

echo ""
echo "=== Post-provision finalize complete ==="
