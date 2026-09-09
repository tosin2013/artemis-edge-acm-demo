#!/usr/bin/env bash
set -euo pipefail
#
# Patch the Showroom user_data ConfigMap to inject the deployment mode.
#
# In multi-hub mode, this adds mode_multi_hub: "true" to the user_data
# so Antora's ifdef::mode_multi_hub[] guards activate at build time.
# In single-hub mode (the default), mode_multi_hub is absent and the
# ifndef guards render Mode 1 content.
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

if [[ -n "${3:-}" ]]; then
  export KUBECONFIG="$3"
fi

if [[ "${MODE}" != "multi-hub" ]]; then
  echo "Mode is '${MODE}' — no Showroom patch needed (single-hub is the default)."
  exit 0
fi

echo "=== Patching Showroom for multi-hub mode ==="

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

  if echo "${CURRENT_DATA}" | grep -q 'mode_multi_hub'; then
    echo "  mode_multi_hub already present. Skipping patch."
  else
    PATCHED_DATA="${CURRENT_DATA}
\"mode_multi_hub\": \"true\""

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
  fi
  echo "  Done: ${NS}"
done

echo "=== Showroom multi-hub mode patch complete ==="
