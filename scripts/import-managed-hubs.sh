#!/usr/bin/env bash
set -euo pipefail
#
# Import regional ACM hubs into the Global Hub as ManagedCluster resources.
#
# This is the Mode 2 post-provision step that bridges independently
# provisioned clusters into a hub-of-hubs topology.  Once imported,
# the existing fleet-gitops ApplicationSets and ACM Policies take over
# automatically (see fleet-gitops/applicationsets/hubs.yaml).
#
# Usage:
#   ./scripts/import-managed-hubs.sh --sandbox <SANDBOX_ID>
#   ./scripts/import-managed-hubs.sh --sandbox ctbz4 --output-dir ~/Development/agnosticd-v2-output
#
# Prerequisites:
#   - All 4 Mode 2 clusters provisioned (global + 3 regional)
#   - oc CLI available and working
#   - Kubeconfigs present in the agd output directory

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
SANDBOX=""
OUTPUT_DIR="${AGD_OUTPUT_DIR:-${HOME}/Development/agnosticd-v2-output}"
IMPORT_TIMEOUT=300   # seconds to wait for JOINED+AVAILABLE
POLL_INTERVAL=10

# ---------------------------------------------------------------------------
# Region mapping — directory prefix → label value
# ---------------------------------------------------------------------------
region_label_for() {
  local prefix="$1"
  case "$prefix" in
    east)    echo "east" ;;
    cen)     echo "central" ;;
    west)    echo "west" ;;
    *)       echo "$prefix" ;;
  esac
}

# ---------------------------------------------------------------------------
# CLI parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sandbox)     SANDBOX="$2"; shift 2 ;;
    --output-dir)  OUTPUT_DIR="$2"; shift 2 ;;
    --timeout)     IMPORT_TIMEOUT="$2"; shift 2 ;;
    -h|--help)
      cat <<EOF
Usage: $0 --sandbox <SANDBOX_ID> [OPTIONS]

Import regional ACM hubs into the Global Hub as ManagedCluster resources.

Options:
  --sandbox ID        Sandbox identifier (required, e.g. ctbz4)
  --output-dir DIR    AgnosticD output directory (default: ~/Development/agnosticd-v2-output)
  --timeout SECS      Seconds to wait for clusters to join (default: 300)
  -h, --help          Show this help message

Examples:
  $0 --sandbox ctbz4
  $0 --sandbox ctbz4 --output-dir /opt/agd-output --timeout 600
EOF
      exit 0
      ;;
    *) echo "ERROR: Unknown option '$1'. Use --help for usage." >&2; exit 1 ;;
  esac
done

if [[ -z "$SANDBOX" ]]; then
  echo "ERROR: --sandbox is required. Example: $0 --sandbox ctbz4" >&2
  exit 1
fi

if ! command -v oc &>/dev/null; then
  echo "ERROR: oc CLI not found in PATH" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Discover hubs
# ---------------------------------------------------------------------------
echo "=== Import Managed Hubs — Sandbox: ${SANDBOX} ==="
echo "Output dir:  ${OUTPUT_DIR}"
echo ""

GLOBAL_KC=""
declare -A REGIONAL_HUBS   # hub_name → kubeconfig_path

for dir in "${OUTPUT_DIR}"/*-"${SANDBOX}"; do
  [[ -d "$dir" ]] || continue
  hub_name="$(basename "$dir")"
  prefix="${hub_name%%-*}"

  # Find the kubeconfig
  kc="${dir}/openshift-cluster_${hub_name}_kubeconfig"
  if [[ ! -f "$kc" ]]; then
    echo "WARN: Kubeconfig not found for ${hub_name} at ${kc}, skipping" >&2
    continue
  fi

  if [[ "$prefix" == "global" ]]; then
    GLOBAL_KC="$kc"
    echo "  Global Hub:     ${hub_name} (${kc})"
  else
    REGIONAL_HUBS["$hub_name"]="$kc"
    echo "  Regional Hub:   ${hub_name} (${kc})"
  fi
done

if [[ -z "$GLOBAL_KC" ]]; then
  echo "ERROR: Global hub kubeconfig not found (expected global-${SANDBOX} in ${OUTPUT_DIR})" >&2
  exit 1
fi

if [[ ${#REGIONAL_HUBS[@]} -eq 0 ]]; then
  echo "ERROR: No regional hub directories found matching *-${SANDBOX} in ${OUTPUT_DIR}" >&2
  exit 1
fi

echo ""
echo "Found ${#REGIONAL_HUBS[@]} regional hub(s) to import."
echo ""

# ---------------------------------------------------------------------------
# Verify Global Hub connectivity
# ---------------------------------------------------------------------------
echo "--- Verifying Global Hub connectivity ---"
if ! KUBECONFIG="$GLOBAL_KC" oc whoami &>/dev/null; then
  echo "ERROR: Cannot connect to Global Hub. Check kubeconfig: ${GLOBAL_KC}" >&2
  exit 1
fi
echo "  Connected as: $(KUBECONFIG="$GLOBAL_KC" oc whoami)"
echo ""

# ---------------------------------------------------------------------------
# Import each regional hub
# ---------------------------------------------------------------------------
for hub_name in $(echo "${!REGIONAL_HUBS[@]}" | tr ' ' '\n' | sort); do
  regional_kc="${REGIONAL_HUBS[$hub_name]}"
  prefix="${hub_name%%-*}"
  region="$(region_label_for "$prefix")"

  echo "--- Importing ${hub_name} (region=${region}) ---"

  # Check if already imported
  if KUBECONFIG="$GLOBAL_KC" oc get managedcluster "$hub_name" &>/dev/null 2>&1; then
    joined=$(KUBECONFIG="$GLOBAL_KC" oc get managedcluster "$hub_name" -o jsonpath='{.status.conditions[?(@.type=="ManagedClusterJoined")].status}' 2>/dev/null || true)
    if [[ "$joined" == "True" ]]; then
      echo "  Already imported and joined — skipping."
      # Ensure labels are correct
      KUBECONFIG="$GLOBAL_KC" oc label managedcluster "$hub_name" \
        hub-tier=regional region="$region" cloud=GCP vendor=OpenShift \
        --overwrite 2>/dev/null
      echo ""
      continue
    fi
    echo "  ManagedCluster exists but not yet joined — re-applying import secret."
  else
    # Create ManagedCluster
    echo "  Creating ManagedCluster..."
    KUBECONFIG="$GLOBAL_KC" oc apply -f - <<MCEOF
apiVersion: cluster.open-cluster-management.io/v1
kind: ManagedCluster
metadata:
  name: ${hub_name}
  labels:
    hub-tier: regional
    region: ${region}
    cloud: GCP
    vendor: OpenShift
spec:
  hubAcceptsClient: true
MCEOF
  fi

  # Wait for the namespace to be created by ACM
  echo "  Waiting for namespace ${hub_name}..."
  for i in $(seq 1 30); do
    if KUBECONFIG="$GLOBAL_KC" oc get namespace "$hub_name" &>/dev/null 2>&1; then
      break
    fi
    sleep 2
  done

  if ! KUBECONFIG="$GLOBAL_KC" oc get namespace "$hub_name" &>/dev/null 2>&1; then
    echo "  ERROR: Namespace ${hub_name} was not created after 60s. ACM may not be healthy." >&2
    continue
  fi

  # Create auto-import secret with the regional hub's kubeconfig
  echo "  Creating auto-import-secret..."
  kc_content="$(cat "$regional_kc")"
  KUBECONFIG="$GLOBAL_KC" oc apply -f - <<SECEOF
apiVersion: v1
kind: Secret
metadata:
  name: auto-import-secret
  namespace: ${hub_name}
stringData:
  autoImportRetry: "5"
  kubeconfig: |
$(echo "$kc_content" | sed 's/^/    /')
type: Opaque
SECEOF

  # Create KlusterletAddonConfig
  echo "  Creating KlusterletAddonConfig..."
  KUBECONFIG="$GLOBAL_KC" oc apply -f - <<KAEOF
apiVersion: agent.open-cluster-management.io/v1
kind: KlusterletAddonConfig
metadata:
  name: ${hub_name}
  namespace: ${hub_name}
spec:
  clusterName: ${hub_name}
  clusterNamespace: ${hub_name}
  applicationManager:
    enabled: true
  certPolicyController:
    enabled: true
  iamPolicyController:
    enabled: true
  policyController:
    enabled: true
  searchCollector:
    enabled: true
KAEOF

  echo "  Import initiated for ${hub_name}."
  echo ""
done

# ---------------------------------------------------------------------------
# Poll for JOINED + AVAILABLE
# ---------------------------------------------------------------------------
echo "=== Waiting for all regional hubs to join (timeout: ${IMPORT_TIMEOUT}s) ==="

all_joined=false
elapsed=0

while [[ $elapsed -lt $IMPORT_TIMEOUT ]]; do
  all_joined=true
  for hub_name in $(echo "${!REGIONAL_HUBS[@]}" | tr ' ' '\n' | sort); do
    joined=$(KUBECONFIG="$GLOBAL_KC" oc get managedcluster "$hub_name" \
      -o jsonpath='{.status.conditions[?(@.type=="ManagedClusterJoined")].status}' 2>/dev/null || true)
    available=$(KUBECONFIG="$GLOBAL_KC" oc get managedcluster "$hub_name" \
      -o jsonpath='{.status.conditions[?(@.type=="ManagedClusterConditionAvailable")].status}' 2>/dev/null || true)

    if [[ "$joined" != "True" || "$available" != "True" ]]; then
      all_joined=false
    fi
  done

  if $all_joined; then
    break
  fi

  sleep "$POLL_INTERVAL"
  elapsed=$((elapsed + POLL_INTERVAL))
  echo "  Polling... (${elapsed}s / ${IMPORT_TIMEOUT}s)"
done

echo ""

if $all_joined; then
  echo "=== All regional hubs imported successfully ==="
else
  echo "WARN: Not all hubs joined within ${IMPORT_TIMEOUT}s. Check status manually:" >&2
  echo "  KUBECONFIG=${GLOBAL_KC} oc get managedclusters" >&2
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "--- ManagedCluster Status ---"
KUBECONFIG="$GLOBAL_KC" oc get managedclusters

echo ""
echo "--- ApplicationSet Status ---"
KUBECONFIG="$GLOBAL_KC" oc get applicationsets -n openshift-gitops 2>/dev/null || echo "  (no ApplicationSets found)"

echo ""
echo "--- ArgoCD Applications (hub-config-*) ---"
KUBECONFIG="$GLOBAL_KC" oc get applications -n openshift-gitops 2>/dev/null | grep -E 'NAME|hub-config' || echo "  (no hub-config Applications yet)"

echo ""
echo "=== Hub import complete ==="
