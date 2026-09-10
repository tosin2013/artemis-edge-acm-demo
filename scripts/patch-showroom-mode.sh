#!/usr/bin/env bash
set -euo pipefail
#
# Patch the Showroom user_data ConfigMap to inject deployment attributes.
#
# Always: injects openshift_api_url if missing (the Showroom workload role
#         doesn't emit it from agnosticd_user_info).
# Multi-hub: also injects mode_multi_hub: "true" so Antora's
#            ifdef::mode_multi_hub[] guards activate at build time.
#
# Usage:
#   ./scripts/patch-showroom-mode.sh <GUID> <MODE> [KUBECONFIG]
#
# Arguments:
#   GUID       - Deployment GUID (e.g. 7d2ft)
#   MODE       - Deployment mode: single-hub or multi-hub
#   KUBECONFIG - (Optional) Path to kubeconfig file
#

GUID="${1:?Usage: $0 <GUID> <MODE> [KUBECONFIG]}"
MODE="${2:?Usage: $0 <GUID> <MODE> [KUBECONFIG]}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${3:-}" ]]; then
  export KUBECONFIG="$3"
fi

# Derive the OpenShift API URL from deployment-info or kubeconfig
OPENSHIFT_API_URL="${OPENSHIFT_API_URL:-}"
if [[ -z "${OPENSHIFT_API_URL}" ]]; then
  DEPLOY_INFO="${SCRIPT_DIR}/../deployment-info.yml"
  if [[ -f "${DEPLOY_INFO}" ]]; then
    OPENSHIFT_API_URL=$(python3 -c "import yaml; print(yaml.safe_load(open('${DEPLOY_INFO}')).get('openshift_api_url',''))" 2>/dev/null || true)
  fi
fi
if [[ -z "${OPENSHIFT_API_URL}" ]]; then
  OPENSHIFT_API_URL=$(oc whoami --show-server 2>/dev/null || true)
fi

echo "=== Patching Showroom ConfigMap ==="

SHOWROOM_NAMESPACES=$(oc get namespaces -o name 2>/dev/null \
  | grep "showroom-${GUID}" \
  | sed 's|namespace/||' || true)

if [[ -z "${SHOWROOM_NAMESPACES}" ]]; then
  echo "WARN: No Showroom namespaces found matching 'showroom-${GUID}*'. Skipping."
  exit 0
fi

for NS in ${SHOWROOM_NAMESPACES}; do
  echo "  Namespace: ${NS}"

  CM_EXISTS=$(oc get configmap showroom-userdata -n "${NS}" -o name 2>/dev/null || true)
  if [[ -z "${CM_EXISTS}" ]]; then
    echo "  WARN: showroom-userdata ConfigMap not found in ${NS}. Skipping."
    continue
  fi

  CURRENT_DATA=$(oc get configmap showroom-userdata -n "${NS}" \
    -o jsonpath='{.data.user_data\.yml}' 2>/dev/null)

  NEEDS_PATCH=false
  PATCHED_DATA="${CURRENT_DATA}"

  # Always inject openshift_api_url if missing
  if [[ -n "${OPENSHIFT_API_URL}" ]] && ! echo "${PATCHED_DATA}" | grep -q 'openshift_api_url'; then
    PATCHED_DATA="${PATCHED_DATA}
\"openshift_api_url\": \"${OPENSHIFT_API_URL}\""
    NEEDS_PATCH=true
    echo "  + openshift_api_url"
  fi

  # Inject mode_multi_hub for multi-hub mode
  if [[ "${MODE}" == "multi-hub" ]] && ! echo "${PATCHED_DATA}" | grep -q 'mode_multi_hub'; then
    PATCHED_DATA="${PATCHED_DATA}
\"mode_multi_hub\": \"true\""
    NEEDS_PATCH=true
    echo "  + mode_multi_hub"
  fi

  if [[ "${NEEDS_PATCH}" == "true" ]]; then
    oc create configmap showroom-userdata \
      --from-literal="user_data.yml=${PATCHED_DATA}" \
      -n "${NS}" --dry-run=client -o yaml \
      | oc apply -f - -n "${NS}"

    echo "  ConfigMap patched. Restarting Showroom content pod..."
    oc delete pod -n "${NS}" -l app.kubernetes.io/component=content --ignore-not-found=true 2>/dev/null || true
    oc delete pod -n "${NS}" -l app=showroom --ignore-not-found=true 2>/dev/null || true

    echo "  Waiting for pod to restart..."
    sleep 5
    oc wait --for=condition=Ready pod -l app.kubernetes.io/part-of=showroom \
      -n "${NS}" --timeout=120s 2>/dev/null || \
      echo "  WARN: Pod readiness wait timed out — check manually."
  else
    echo "  No patch needed."
  fi
  echo "  Done: ${NS}"
done

echo "=== Showroom ConfigMap patch complete ==="
