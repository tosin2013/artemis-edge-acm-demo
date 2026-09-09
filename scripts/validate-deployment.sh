#!/usr/bin/env bash
# scripts/validate-deployment.sh — Post-deploy E2E validation
#
# Validates that all workloads deployed by agd provision are healthy.
# Used by project-onboard (onboard.yml) and bootstrap.sh as a post-deploy gate.
#
# Usage:
#   ./scripts/validate-deployment.sh [--kubeconfig PATH]
#
# Exit codes:
#   0 — All checks passed
#   1 — One or more required checks failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

KUBECONFIG_PATH="${KUBECONFIG:-}"
PASSED=0
FAILED=0
WARNED=0
TOTAL=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --kubeconfig) KUBECONFIG_PATH="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -n "$KUBECONFIG_PATH" ]]; then
  export KUBECONFIG="$KUBECONFIG_PATH"
fi

check() {
  local name="$1"
  local required="$2"
  local cmd="$3"
  TOTAL=$((TOTAL + 1))

  if eval "$cmd" > /dev/null 2>&1; then
    echo "  [PASS] $name"
    PASSED=$((PASSED + 1))
  elif [[ "$required" == "true" ]]; then
    echo "  [FAIL] $name"
    FAILED=$((FAILED + 1))
  else
    echo "  [WARN] $name"
    WARNED=$((WARNED + 1))
  fi
}

echo ""
echo "--- Post-Deploy Validation ---"
echo ""

check "OpenShift API reachable" true \
  "oc whoami"

check "cert-manager operator Succeeded" true \
  "oc get csv -n cert-manager-operator -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Succeeded"

check "htpasswd OAuth configured" true \
  "oc get oauth cluster -o jsonpath='{.spec.identityProviders}' 2>/dev/null | grep -q htpasswd"

check "RHACM MultiClusterHub Running" true \
  "oc get mch -n open-cluster-management -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running"

check "OpenShift GitOps operator Succeeded" true \
  "oc get csv -n openshift-gitops-operator -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Succeeded"

check "ArgoCD route available" true \
  "oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}' 2>/dev/null | grep -q ."

check "ArgoCD field-content Synced" true \
  "oc get applications.argoproj.io field-content -n openshift-gitops -o jsonpath='{.status.sync.status}' 2>/dev/null | grep -q Synced"

check "ArgoCD field-content Healthy" true \
  "oc get applications.argoproj.io field-content -n openshift-gitops -o jsonpath='{.status.health.status}' 2>/dev/null | grep -q Healthy"

check "artemis namespace exists" true \
  "oc get ns artemis"

check "AMQ Broker operator Succeeded" true \
  "oc get csv -n artemis -o jsonpath='{range .items[*]}{.metadata.name}{\" \"}{.status.phase}{\"\\n\"}{end}' 2>/dev/null | grep -q 'amq-broker.*Succeeded'"

check "hub-01-broker pod Running" true \
  "oc get pod -n artemis -l ActiveMQArtemis=hub-01-broker -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running"

check "spoke-01-broker pod Running" true \
  "oc get pod -n artemis -l ActiveMQArtemis=spoke-01-broker -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running"

check "spoke-02-broker pod Running" true \
  "oc get pod -n artemis -l ActiveMQArtemis=spoke-02-broker -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running"

check "spoke-03-broker pod Running" true \
  "oc get pod -n artemis -l ActiveMQArtemis=spoke-03-broker -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running"

check "keycloak namespace exists" true \
  "oc get ns keycloak"

check "Keycloak operator Succeeded" true \
  "oc get csv -n keycloak -o jsonpath='{range .items[*]}{.metadata.name}{\" \"}{.status.phase}{\"\\n\"}{end}' 2>/dev/null | grep -q 'keycloak.*Succeeded'"

check "Keycloak pod Running" true \
  "oc get pod -n keycloak -l app=keycloak -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running"

check "Showroom pods running" false \
  "oc get pods -l app=showroom -A --no-headers 2>/dev/null | grep -q Running"

check "Monitoring ConfigMaps present" false \
  "oc get configmap artemis-amq-broker-dashboard -n open-cluster-management-observability 2>/dev/null"

echo ""
REQUIRED_TOTAL=$((PASSED + FAILED))
echo "  Readiness: ${PASSED}/${REQUIRED_TOTAL} required checks passed (${WARNED} warning(s))"
echo ""

if [[ $FAILED -gt 0 ]]; then
  echo "  BLOCKED: ${FAILED} required check(s) failed."
  exit 1
else
  echo "  ✅ All required checks passed. Deployment is healthy."
  exit 0
fi
