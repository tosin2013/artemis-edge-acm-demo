#!/usr/bin/env bash
# collect-evidence.sh — Capture PLAYBOOK-infra evidence for spec 001-mode2-gcp-deploy
# Run this AFTER all 4 tiers are deployed and import-managed-hubs.sh has completed.
#
# Usage: ./scripts/collect-evidence.sh --sandbox <SANDBOX>
#
# Requires: oc (logged into Global Hub), gcloud (authenticated)

set -euo pipefail

EVIDENCE_DIR="docs/evidence/001-mode2-gcp-deploy"

# Parse args
SANDBOX=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --sandbox) SANDBOX="$2"; shift 2 ;;
    *) echo "Usage: $0 --sandbox <SANDBOX>"; exit 1 ;;
  esac
done

if [[ -z "$SANDBOX" ]]; then
  echo "Error: --sandbox is required"
  echo "Usage: $0 --sandbox <SANDBOX>"
  exit 1
fi

BASE_DOMAIN="${SANDBOX}.gcp.redhatworkshops.io"
GLOBAL_API="https://api.hub.${BASE_DOMAIN}:6443"
EAST_API="https://api.hub-east.${BASE_DOMAIN}:6443"
CENTRAL_API="https://api.hub-central.${BASE_DOMAIN}:6443"
WEST_API="https://api.hub-west.${BASE_DOMAIN}:6443"
OUTPUT_DIR="${AGD_OUTPUT_DIR:-${HOME}/Development/agnosticd-v2-output}"

# Prefer the kubeconfig written by agd. oc login without a token drops the command.
use_cluster() {
  local tier="$1"
  local api="$2"
  local kc="${OUTPUT_DIR}/${tier}-${SANDBOX}/openshift-cluster_${tier}-${SANDBOX}_kubeconfig"
  if [[ -f "$kc" ]]; then
    export KUBECONFIG="$kc"
    return 0
  fi
  oc login "${api}" --insecure-skip-tls-verify 2>/dev/null || true
}

echo "========================================"
echo "Evidence collection for spec 001"
echo "Sandbox: ${SANDBOX}"
echo "Base domain: ${BASE_DOMAIN}"
echo "========================================"

# ── Rung 3: Reconcile ──────────────────────────────────────
echo ""
echo "=== RUNG 3: Reconcile ==="
mkdir -p "${EVIDENCE_DIR}/rung3"

echo "Capturing Global Hub status..."
use_cluster global "${GLOBAL_API}"

oc get applications.argoproj.io -n openshift-gitops -o wide 2>&1 \
  | tee "${EVIDENCE_DIR}/rung3/argocd-global.txt"
oc get applicationsets.argoproj.io -n openshift-gitops -o wide 2>&1 \
  | tee "${EVIDENCE_DIR}/rung3/applicationsets-global.txt"
oc get managedclusters -o wide 2>&1 \
  | tee "${EVIDENCE_DIR}/rung3/managedclusters.txt"
oc get multiclusterglobalhub -A 2>&1 \
  | tee "${EVIDENCE_DIR}/rung3/globalhub-status.txt"

for hub in east cen west; do
  case $hub in
    east) API="${EAST_API}" ;;
    cen) API="${CENTRAL_API}" ;;
    west) API="${WEST_API}" ;;
  esac
  echo ""
  echo "Capturing ${hub} hub status..."
  use_cluster "${hub}" "${API}"

  oc get applications.argoproj.io -n openshift-gitops -o wide 2>&1 \
    | tee "${EVIDENCE_DIR}/rung3/argocd-${hub}.txt"
  oc get multiclusterhub -A 2>&1 \
    | tee "${EVIDENCE_DIR}/rung3/acm-${hub}.txt"
  oc get activemqartemis -A 2>&1 \
    | tee "${EVIDENCE_DIR}/rung3/amq-${hub}.txt"
done

echo ""
echo "Rung 3 artifacts saved to ${EVIDENCE_DIR}/rung3/"

# ── Rung 4: Security ───────────────────────────────────────
echo ""
echo "=== RUNG 4: Security ==="
mkdir -p "${EVIDENCE_DIR}/rung4"

for ctx in global east cen west; do
  case $ctx in
    global) API="${GLOBAL_API}" ;;
    east) API="${EAST_API}" ;;
    cen) API="${CENTRAL_API}" ;;
    west) API="${WEST_API}" ;;
  esac
  echo "Capturing RBAC + SCC for ${ctx}..."
  use_cluster "${ctx}" "${API}"

  {
    echo "=== ${ctx}: cluster-admin bindings ==="
    oc get clusterrolebindings -o json \
      | jq '.items[] | select(.roleRef.name=="cluster-admin") | {name: .metadata.name, subjects: .subjects}' 2>&1
    echo ""
  } >> "${EVIDENCE_DIR}/rung4/rbac.log"

  {
    echo "=== ${ctx}: SCC per pod (sample — first 50) ==="
    oc get pods -A -o json \
      | jq -r '.items[:50][] | "\(.metadata.namespace)/\(.metadata.name) \(.metadata.annotations["openshift.io/scc"] // "N/A")"' 2>&1
    echo ""
  } >> "${EVIDENCE_DIR}/rung4/scc.log"
done

echo "Rung 4 artifacts saved to ${EVIDENCE_DIR}/rung4/"

# ── Rung 5: Functional ─────────────────────────────────────
echo ""
echo "=== RUNG 5: Functional ==="
mkdir -p "${EVIDENCE_DIR}/rung5"

if [[ -x scripts/validate-deployment.sh ]]; then
  : > "${EVIDENCE_DIR}/rung5/validate.log"
  for tier in global east cen west; do
    echo "=== validate ${tier} ===" | tee -a "${EVIDENCE_DIR}/rung5/validate.log"
    use_cluster "${tier}" "${GLOBAL_API}"
    scripts/validate-deployment.sh --mode multi-hub 2>&1 \
      | tee -a "${EVIDENCE_DIR}/rung5/validate.log" || true
    echo "" | tee -a "${EVIDENCE_DIR}/rung5/validate.log"
  done
else
  echo "WARNING: scripts/validate-deployment.sh not found or not executable" \
    | tee "${EVIDENCE_DIR}/rung5/validate.log"
fi

# Smoke tests
{
  echo "=== Smoke tests ==="
  echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""

  for hub in east cen west; do
    case $hub in
      east) DOMAIN="apps.hub-east.${BASE_DOMAIN}" ;;
      cen) DOMAIN="apps.hub-central.${BASE_DOMAIN}" ;;
      west) DOMAIN="apps.hub-west.${BASE_DOMAIN}" ;;
    esac
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "https://openshift-gitops-server-openshift-gitops.${DOMAIN}/" 2>/dev/null || echo "000")
    echo "ArgoCD (${hub}): HTTP ${HTTP_CODE}"
  done

  GLOBAL_DOMAIN="apps.hub.${BASE_DOMAIN}"
  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "https://openshift-gitops-server-openshift-gitops.${GLOBAL_DOMAIN}/" 2>/dev/null || echo "000")
  echo "ArgoCD (global): HTTP ${HTTP_CODE}"

} | tee "${EVIDENCE_DIR}/rung5/smoke-tests.log"

echo "Rung 5 artifacts saved to ${EVIDENCE_DIR}/rung5/"

echo ""
echo "========================================"
echo "Evidence collection complete."
echo "Review artifacts in: ${EVIDENCE_DIR}/"
echo "Then tick off VERIFY.md checklist items."
echo "========================================"
