#!/usr/bin/env bash
set -euo pipefail
#
# Deploy SNO spoke clusters from the hub using ACM/Hive on GCP.
#
# This script is designed to be run by the demo user from the Showroom
# terminal. It extracts credentials from the hub cluster (ACM credential
# secret or bastion files), creates per-spoke namespaces and secrets,
# patches the ArgoCD application, and monitors Hive provisioning.
#
# Prerequisites:
#   - oc logged in with cluster-admin
#   - Hive running on the hub (installed by RHACM)
#   - ArgoCD field-content app exists and is Synced
#   - GCP credential created in RHACM Console (or ~/gcp-service-account.json)
#
# Usage:
#   ./scripts/deploy-spokes.sh                    # 2 spokes (default)
#   ./scripts/deploy-spokes.sh --clusters 3       # 3 spokes
#   ./scripts/deploy-spokes.sh --status           # check provisioning status
#   ./scripts/deploy-spokes.sh --destroy          # tear down spokes
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Defaults
CLUSTER_COUNT=2
MAX_CLUSTERS=3
TIMEOUT_MIN=60
ACTION="provision"
GCP_KEY_PATH="${HOME}/gcp-service-account.json"
ACM_CRED_NS="gcp-credentials"
ACM_CRED_NAME="gcp-credentials"
CLUSTER_IMAGE_SET="img4.22.12-x86-64-appsub"
GCP_REGION="us-east1"
MACHINE_TYPE="n2-standard-8"
SSH_KEY_PATH="${HOME}/.ssh/sno-edge-key"

SPOKE_NAMES=("sno-edge-01" "sno-edge-02" "sno-edge-03")
SPOKE_REGIONS=("NY" "NJ" "CT")

# Parse CLI args
while [[ $# -gt 0 ]]; do
  case $1 in
    --clusters) CLUSTER_COUNT="$2"; shift 2 ;;
    --timeout) TIMEOUT_MIN="$2"; shift 2 ;;
    --gcp-key) GCP_KEY_PATH="$2"; shift 2 ;;
    --image-set) CLUSTER_IMAGE_SET="$2"; shift 2 ;;
    --status) ACTION="status"; shift ;;
    --destroy) ACTION="destroy"; shift ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Provision SNO spoke clusters from the hub using ACM/Hive."
      echo ""
      echo "Options:"
      echo "  --clusters N      Number of SNO spokes to provision (default: 2, max: 3)"
      echo "  --timeout MIN     Max wait for provisioning in minutes (default: 60)"
      echo "  --gcp-key PATH    GCP service account JSON (default: ~/gcp-service-account.json)"
      echo "  --image-set NAME  ClusterImageSet name (default: img4.22.12-x86-64-appsub)"
      echo "  --status          Check current spoke provisioning status"
      echo "  --destroy         Tear down spoke clusters"
      echo "  -h, --help        Show this help"
      echo ""
      echo "Examples:"
      echo "  $0                     # Provision 2 SNO spokes"
      echo "  $0 --clusters 3        # Provision 3 SNO spokes"
      echo "  $0 --status            # Check provisioning progress"
      echo "  $0 --destroy           # Tear down all spokes"
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ "$CLUSTER_COUNT" -gt "$MAX_CLUSTERS" ]]; then
  echo "ERROR: Maximum $MAX_CLUSTERS spoke clusters supported." >&2
  exit 1
fi

# ── Helpers ──────────────────────────────────────────────────────────

log_step() { echo ""; echo "[$1] $2"; }
log_ok()   { echo "  ✓ $1"; }
log_warn() { echo "  ⚠ $1"; }
log_fail() { echo "  ✗ $1" >&2; }

# ── Status action ────────────────────────────────────────────────────

if [[ "$ACTION" == "status" ]]; then
  echo "=== Spoke Cluster Status ==="
  echo ""
  echo "--- ClusterDeployments ---"
  oc get clusterdeployments -A -o custom-columns=\
NAME:.metadata.name,NAMESPACE:.metadata.namespace,INSTALLED:.spec.installed,\
PLATFORM:.spec.platform.gcp.region 2>/dev/null || echo "  No ClusterDeployments found"
  echo ""
  echo "--- ManagedClusters ---"
  oc get managedcluster -o custom-columns=\
NAME:.metadata.name,REGION:.metadata.labels.edge-region,\
PROVIDER:.metadata.labels.cloud-provider,\
AVAILABLE:'.status.conditions[?(@.type=="ManagedClusterConditionAvailable")].status' 2>/dev/null
  echo ""
  echo "--- RHACM Policies ---"
  oc get policy -n ztp-policies 2>/dev/null || echo "  No policies in ztp-policies namespace"
  exit 0
fi

# ── Destroy action ───────────────────────────────────────────────────

if [[ "$ACTION" == "destroy" ]]; then
  echo "=== Destroying Spoke Clusters ==="
  echo ""

  for i in $(seq 0 $((CLUSTER_COUNT - 1))); do
    SPOKE="${SPOKE_NAMES[$i]}"
    echo "--- Deleting $SPOKE ---"
    oc delete managedcluster "$SPOKE" --ignore-not-found=true 2>/dev/null || true
    oc delete clusterdeployment "$SPOKE" -n "$SPOKE" --ignore-not-found=true 2>/dev/null || true
    oc delete klusterletaddonconfig "$SPOKE" -n "$SPOKE" --ignore-not-found=true 2>/dev/null || true
  done

  echo ""
  echo "Waiting for Hive to deprovision clusters (this may take several minutes)..."
  TIMEOUT_SEC=$((TIMEOUT_MIN * 60))
  ELAPSED=0
  while [[ $ELAPSED -lt $TIMEOUT_SEC ]]; do
    REMAINING=$(oc get clusterdeployments -A --no-headers 2>/dev/null | wc -l)
    if [[ "$REMAINING" -eq 0 ]]; then
      echo "  All ClusterDeployments removed."
      break
    fi
    echo "  $REMAINING ClusterDeployment(s) still deprovisioning... (${ELAPSED}s elapsed)"
    sleep 30
    ELAPSED=$((ELAPSED + 30))
  done

  echo ""
  echo "--- Cleaning up namespaces ---"
  for i in $(seq 0 $((CLUSTER_COUNT - 1))); do
    SPOKE="${SPOKE_NAMES[$i]}"
    oc delete namespace "$SPOKE" --ignore-not-found=true 2>/dev/null || true
  done
  oc delete namespace ztp-policies --ignore-not-found=true 2>/dev/null || true

  echo ""
  echo "--- Patching ArgoCD to disable spokeProvisioning ---"
  CURRENT_VALUES=$(oc get application.argoproj.io field-content -n openshift-gitops \
    -o jsonpath='{.spec.source.helm.values}' 2>/dev/null)
  PATCHED_VALUES=$(echo "$CURRENT_VALUES" | python3 -c "
import sys, yaml
v = yaml.safe_load(sys.stdin.read())
if v and 'spokeProvisioning' in v:
    v['spokeProvisioning']['enabled'] = False
    v['spokeProvisioning'].pop('clusters', None)
print(yaml.dump(v, default_flow_style=False))
")
  oc patch application.argoproj.io field-content -n openshift-gitops \
    --type merge -p "{\"spec\":{\"source\":{\"helm\":{\"values\":$(echo "$PATCHED_VALUES" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')}}}}" 2>/dev/null
  log_ok "ArgoCD patched (spokeProvisioning.enabled: false)"

  echo ""
  echo "=== Spoke cluster teardown complete ==="
  exit 0
fi

# ══════════════════════════════════════════════════════════════════════
# Provision action
# ══════════════════════════════════════════════════════════════════════

SELECTED_SPOKES=("${SPOKE_NAMES[@]:0:$CLUSTER_COUNT}")
SELECTED_REGIONS=("${SPOKE_REGIONS[@]:0:$CLUSTER_COUNT}")

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Artemis Edge — SNO Spoke Provisioning                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# ── Step 1: Pre-flight checks ────────────────────────────────────────

log_step "1/6" "Pre-flight checks..."

# Check oc login
oc whoami &>/dev/null || { log_fail "Not logged in. Run: oc login"; exit 1; }
log_ok "Logged in as $(oc whoami)"

# Check Hive
HIVE_PODS=$(oc get pods -n hive --no-headers 2>/dev/null | grep -c Running || true)
if [[ "$HIVE_PODS" -lt 1 ]]; then
  log_fail "Hive not running. Check: oc get pods -n hive"
  exit 1
fi
log_ok "Hive running ($HIVE_PODS pods)"

# Check ClusterImageSet
oc get clusterimagesets "$CLUSTER_IMAGE_SET" &>/dev/null || {
  log_fail "ClusterImageSet '$CLUSTER_IMAGE_SET' not found."
  echo "  Available 4.22 sets:"
  oc get clusterimagesets 2>/dev/null | grep '4\.22.*x86' | head -5
  exit 1
}
log_ok "ClusterImageSet: $CLUSTER_IMAGE_SET"

# Check ArgoCD app
oc get application.argoproj.io field-content -n openshift-gitops &>/dev/null || {
  log_fail "ArgoCD app 'field-content' not found in openshift-gitops namespace."
  exit 1
}
log_ok "ArgoCD app field-content exists"

# Check GCP vCPU quota (requires gcloud)
if command -v gcloud &>/dev/null; then
  VCPUS_NEEDED=$((CLUSTER_COUNT * 8))
  GCP_PROJECT_FOR_QUOTA=$(oc get infrastructure cluster \
    -o jsonpath='{.status.platformStatus.gcp.projectID}' 2>/dev/null || true)
  if [[ -n "$GCP_PROJECT_FOR_QUOTA" ]]; then
    N2_AVAIL=$(gcloud compute regions describe "$GCP_REGION" \
      --project="$GCP_PROJECT_FOR_QUOTA" --format='json(quotas)' 2>/dev/null \
      | python3 -c "
import json, sys
data = json.load(sys.stdin)
for q in data.get('quotas', []):
    if q.get('metric') == 'N2_CPUS':
        print(int(q.get('limit',0) - q.get('usage',0)))
        break
" 2>/dev/null || echo "")
    if [[ -n "$N2_AVAIL" && "$N2_AVAIL" -gt 0 ]]; then
      if [[ "$N2_AVAIL" -lt "$VCPUS_NEEDED" ]]; then
        log_fail "Insufficient N2 vCPU quota: need ${VCPUS_NEEDED}, only ${N2_AVAIL} available in ${GCP_REGION}"
        echo "  Request a quota increase or reduce --clusters count."
        exit 1
      fi
      log_ok "GCP N2 vCPU quota: ${N2_AVAIL} available (need ${VCPUS_NEEDED} for ${CLUSTER_COUNT} spokes)"
    else
      log_warn "Could not determine N2 vCPU quota — proceeding (check manually if provisioning fails)"
    fi
  else
    log_warn "Cannot determine GCP project — skipping quota check"
  fi
else
  log_warn "gcloud CLI not found — skipping GCP quota check"
fi

# ── Step 2: Extract credentials from hub ─────────────────────────────

log_step "2/6" "Extracting credentials from hub..."

# Try ACM credential secret first, then fall back to bastion files
GCP_CREDS_JSON=""
PULL_SECRET_JSON=""
SSH_PUB_KEY=""
SSH_PRIV_KEY=""
BASE_DOMAIN=""
GCP_PROJECT_ID=""

# GCP Project ID from infrastructure resource
GCP_PROJECT_ID=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.gcp.projectID}' 2>/dev/null || true)
if [[ -z "$GCP_PROJECT_ID" ]]; then
  if [[ -f "${PROJECT_ROOT}/deployment-info.yml" ]]; then
    GCP_PROJECT_ID=$(python3 -c "import yaml; print(yaml.safe_load(open('${PROJECT_ROOT}/deployment-info.yml')).get('gcp_project_id',''))" 2>/dev/null || true)
  fi
fi
[[ -n "$GCP_PROJECT_ID" ]] && log_ok "GCP Project: $GCP_PROJECT_ID" || { log_fail "Cannot determine GCP project ID"; exit 1; }

# Base domain: strip "hub." prefix from cluster base domain to get sandbox domain
CLUSTER_BASE=$(oc get dns cluster -o jsonpath='{.spec.baseDomain}' 2>/dev/null || true)
BASE_DOMAIN="${CLUSTER_BASE#hub.}"
[[ -n "$BASE_DOMAIN" ]] && log_ok "Base domain: $BASE_DOMAIN" || { log_fail "Cannot determine base domain"; exit 1; }

# GCP credentials: try ACM secret, then bastion file
ACM_SECRET_EXISTS=$(oc get secret "$ACM_CRED_NAME" -n "$ACM_CRED_NS" -o name 2>/dev/null || true)
if [[ -n "$ACM_SECRET_EXISTS" ]]; then
  log_ok "Using ACM credential: $ACM_CRED_NS/$ACM_CRED_NAME"
  GCP_CREDS_JSON=$(oc get secret "$ACM_CRED_NAME" -n "$ACM_CRED_NS" \
    -o jsonpath='{.data.osServiceAccount\.json}' 2>/dev/null | base64 -d 2>/dev/null || true)
  PULL_SECRET_JSON=$(oc get secret "$ACM_CRED_NAME" -n "$ACM_CRED_NS" \
    -o jsonpath='{.data.pullSecret}' 2>/dev/null | base64 -d 2>/dev/null || true)
  SSH_PUB_KEY=$(oc get secret "$ACM_CRED_NAME" -n "$ACM_CRED_NS" \
    -o jsonpath='{.data.ssh-publickey}' 2>/dev/null | base64 -d 2>/dev/null || true)
  SSH_PRIV_KEY=$(oc get secret "$ACM_CRED_NAME" -n "$ACM_CRED_NS" \
    -o jsonpath='{.data.ssh-privatekey}' 2>/dev/null | base64 -d 2>/dev/null || true)
fi

# Fallback: GCP key from bastion file
if [[ -z "$GCP_CREDS_JSON" ]]; then
  if [[ -f "$GCP_KEY_PATH" ]]; then
    GCP_CREDS_JSON=$(cat "$GCP_KEY_PATH")
    log_ok "GCP credentials: $GCP_KEY_PATH (bastion fallback)"
  else
    log_fail "No GCP credentials found. Create an ACM credential or place key at $GCP_KEY_PATH"
    exit 1
  fi
fi

# Fallback: pull secret from cluster
if [[ -z "$PULL_SECRET_JSON" ]]; then
  PULL_SECRET_JSON=$(oc get secret pull-secret -n openshift-config \
    -o jsonpath='{.data.\.dockerconfigjson}' 2>/dev/null | base64 -d 2>/dev/null || true)
  [[ -n "$PULL_SECRET_JSON" ]] && log_ok "Pull secret: extracted from openshift-config" || {
    log_fail "Cannot extract pull secret"; exit 1;
  }
fi

# Fallback: SSH key from bastion
if [[ -z "$SSH_PUB_KEY" ]]; then
  if [[ -f "${HOME}/.ssh/google_compute_engine.pub" ]]; then
    SSH_PUB_KEY=$(cat "${HOME}/.ssh/google_compute_engine.pub")
    SSH_PRIV_KEY=$(cat "${HOME}/.ssh/google_compute_engine" 2>/dev/null || true)
    log_ok "SSH key: ~/.ssh/google_compute_engine (bastion fallback)"
  elif [[ -f "$SSH_KEY_PATH.pub" ]]; then
    SSH_PUB_KEY=$(cat "$SSH_KEY_PATH.pub")
    SSH_PRIV_KEY=$(cat "$SSH_KEY_PATH" 2>/dev/null || true)
    log_ok "SSH key: $SSH_KEY_PATH"
  else
    log_warn "No SSH key found — generating new keypair..."
    ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -q
    SSH_PUB_KEY=$(cat "$SSH_KEY_PATH.pub")
    SSH_PRIV_KEY=$(cat "$SSH_KEY_PATH")
    log_ok "SSH key: generated $SSH_KEY_PATH"
  fi
fi

# ── Step 3: Create per-spoke namespaces and secrets ──────────────────

log_step "3/6" "Creating spoke namespaces & secrets..."

for i in $(seq 0 $((CLUSTER_COUNT - 1))); do
  SPOKE="${SELECTED_SPOKES[$i]}"
  echo "  --- $SPOKE (${SELECTED_REGIONS[$i]}) ---"

  oc create namespace "$SPOKE" --dry-run=client -o yaml 2>/dev/null | oc apply -f - 2>/dev/null
  log_ok "Namespace: $SPOKE"

  oc create secret generic "${SPOKE}-gcp-creds" \
    --from-literal=osServiceAccount.json="$GCP_CREDS_JSON" \
    -n "$SPOKE" --dry-run=client -o yaml 2>/dev/null | oc apply -f - 2>/dev/null
  log_ok "Secret: ${SPOKE}-gcp-creds"

  oc create secret generic "${SPOKE}-pull-secret" \
    --from-literal=.dockerconfigjson="$PULL_SECRET_JSON" \
    --type=kubernetes.io/dockerconfigjson \
    -n "$SPOKE" --dry-run=client -o yaml 2>/dev/null | oc apply -f - 2>/dev/null
  log_ok "Secret: ${SPOKE}-pull-secret"

  if [[ -n "$SSH_PRIV_KEY" ]]; then
    oc create secret generic "${SPOKE}-ssh-private-key" \
      --from-literal=ssh-privatekey="$SSH_PRIV_KEY" \
      -n "$SPOKE" --dry-run=client -o yaml 2>/dev/null | oc apply -f - 2>/dev/null
    log_ok "Secret: ${SPOKE}-ssh-private-key"
  else
    log_warn "No SSH private key — ${SPOKE}-ssh-private-key not created"
  fi
done

# ── Step 4: Patch ArgoCD application ─────────────────────────────────

log_step "4/6" "Patching ArgoCD field-content application..."

# Build the cluster list YAML for the Helm values
CLUSTER_YAML=""
for i in $(seq 0 $((CLUSTER_COUNT - 1))); do
  CLUSTER_YAML="${CLUSTER_YAML}
    - name: ${SELECTED_SPOKES[$i]}
      region: ${SELECTED_REGIONS[$i]}"
done

CURRENT_VALUES=$(oc get application.argoproj.io field-content -n openshift-gitops \
  -o jsonpath='{.spec.source.helm.values}' 2>/dev/null)

PATCHED_VALUES=$(echo "$CURRENT_VALUES" | python3 -c "
import sys, yaml

v = yaml.safe_load(sys.stdin.read()) or {}
v['spokeProvisioning'] = {
    'enabled': True,
    'baseDomain': '${BASE_DOMAIN}',
    'gcpProjectID': '${GCP_PROJECT_ID}',
    'gcpRegion': '${GCP_REGION}',
    'clusterImageSet': '${CLUSTER_IMAGE_SET}',
    'sshPublicKey': '''${SSH_PUB_KEY}''',
    'networkType': 'OVNKubernetes',
    'workerMachineType': '${MACHINE_TYPE}',
    'masterMachineType': '${MACHINE_TYPE}',
    'clusters': [
$(for i in $(seq 0 $((CLUSTER_COUNT - 1))); do
  echo "        {'name': '${SELECTED_SPOKES[$i]}', 'region': '${SELECTED_REGIONS[$i]}'},"
done)
    ],
}
print(yaml.dump(v, default_flow_style=False))
")

oc patch application.argoproj.io field-content -n openshift-gitops \
  --type merge \
  -p "{\"spec\":{\"source\":{\"helm\":{\"values\":$(echo "$PATCHED_VALUES" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')}}}}" 2>/dev/null

log_ok "ArgoCD patched with spokeProvisioning.enabled=true"

# Trigger a sync
echo "  Syncing ArgoCD application..."
oc annotate application.argoproj.io field-content -n openshift-gitops \
  argocd.argoproj.io/refresh=hard --overwrite 2>/dev/null || true
sleep 10

SYNC_STATUS=$(oc get application.argoproj.io field-content -n openshift-gitops \
  -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
log_ok "ArgoCD sync status: $SYNC_STATUS"

# ── Step 5: Monitor Hive provisioning ────────────────────────────────

log_step "5/6" "Waiting for Hive provisioning..."
echo ""
echo "  Spokes: ${SELECTED_SPOKES[*]}"
echo "  Timeout: ${TIMEOUT_MIN} minutes"
echo ""

TIMEOUT_SEC=$((TIMEOUT_MIN * 60))
ELAPSED=0
ALL_INSTALLED=false

while [[ $ELAPSED -lt $TIMEOUT_SEC ]]; do
  echo "  ┌─────────────────┬───────────┬────────────┬──────────┐"
  echo "  │ CLUSTER         │ INSTALLED │ POWER      │ AGE      │"
  echo "  ├─────────────────┼───────────┼────────────┼──────────┤"

  INSTALLED_COUNT=0
  for i in $(seq 0 $((CLUSTER_COUNT - 1))); do
    SPOKE="${SELECTED_SPOKES[$i]}"
    INSTALLED=$(oc get clusterdeployment "$SPOKE" -n "$SPOKE" \
      -o jsonpath='{.spec.installed}' 2>/dev/null || echo "pending")
    POWER=$(oc get clusterdeployment "$SPOKE" -n "$SPOKE" \
      -o jsonpath='{.status.powerState}' 2>/dev/null || echo "—")
    AGE=$(oc get clusterdeployment "$SPOKE" -n "$SPOKE" \
      -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || echo "—")

    if [[ "$INSTALLED" == "true" ]]; then
      INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
      MARK="✓"
    else
      MARK=" "
    fi
    printf "  │ %-15s │ %-9s │ %-10s │ %-8s │ %s\n" \
      "$SPOKE" "$INSTALLED" "$POWER" "$AGE" "$MARK"
  done
  echo "  └─────────────────┴───────────┴────────────┴──────────┘"

  if [[ "$INSTALLED_COUNT" -eq "$CLUSTER_COUNT" ]]; then
    ALL_INSTALLED=true
    break
  fi

  REMAINING_MIN=$(( (TIMEOUT_SEC - ELAPSED) / 60 ))
  echo "  ...polling in 60s (${REMAINING_MIN}m remaining)..."
  echo ""
  sleep 60
  ELAPSED=$((ELAPSED + 60))
done

if [[ "$ALL_INSTALLED" != "true" ]]; then
  log_warn "Timeout reached. $INSTALLED_COUNT/$CLUSTER_COUNT clusters installed."
  echo "  Run '$0 --status' to check progress."
  echo "  Provisioning continues in the background."
fi

# ── Step 6: Verify ManagedClusters ───────────────────────────────────

log_step "6/6" "Verifying ManagedClusters..."
echo ""

oc get managedcluster -o custom-columns=\
NAME:.metadata.name,\
REGION:.metadata.labels.edge-region,\
PROVIDER:.metadata.labels.cloud-provider,\
AVAILABLE:'.status.conditions[?(@.type=="ManagedClusterConditionAvailable")].status' 2>/dev/null

echo ""

# Check RHACM policies
POLICY_COUNT=$(oc get policy -n ztp-policies --no-headers 2>/dev/null | wc -l || echo 0)
if [[ "$POLICY_COUNT" -gt 0 ]]; then
  log_ok "RHACM policies: $POLICY_COUNT policies in ztp-policies"
  oc get policy -n ztp-policies 2>/dev/null
else
  log_warn "No RHACM policies found (may still be syncing)"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Spoke provisioning complete!                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo "  - Review ClusterDeployments: oc get clusterdeployments -A"
echo "  - Check policies:            oc get policy -n ztp-policies"
echo "  - Continue to Module 03:     AMQ Brokers and Federation"
