#!/usr/bin/env bash
set -euo pipefail
#
# Point the Showroom terminal (and Maven) at the writable PVC (/home/lab-user).
# The RHDP terminal image sets passwd home to /data, which is not mounted.
# OpenJDK user.home comes from passwd, not $HOME, so Maven still uses /data/.m2
# unless JAVA_TOOL_OPTIONS / MAVEN_OPTS override it.
#
# Usage:
#   ./scripts/patch-showroom-home.sh <GUID> [KUBECONFIG]
#

GUID="${1:?Usage: $0 <GUID> [KUBECONFIG]}"

if [[ -n "${2:-}" ]]; then
  export KUBECONFIG="$2"
fi

HOME_DIR="/home/lab-user"
MAVEN_HOME="${HOME_DIR}/.m2"
JAVA_TOOL_OPTIONS="-Duser.home=${HOME_DIR}"
MAVEN_OPTS="-Dmaven.repo.local=${MAVEN_HOME}/repository"

echo "=== Patching Showroom terminal HOME / Maven repo ==="

SHOWROOM_NAMESPACES=$(oc get namespaces -o name 2>/dev/null \
  | grep "showroom-${GUID}" \
  | sed 's|namespace/||' || true)

if [[ -z "${SHOWROOM_NAMESPACES}" ]]; then
  echo "WARN: No Showroom namespaces found matching 'showroom-${GUID}*'. Skipping."
  exit 0
fi

for NS in ${SHOWROOM_NAMESPACES}; do
  echo "  Namespace: ${NS}"

  DEPLOYS=$(oc get deploy -n "${NS}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
  if [[ -z "${DEPLOYS}" ]]; then
    echo "  WARN: No Deployments in ${NS}. Skipping."
    continue
  fi

  for DEPLOY in ${DEPLOYS}; do
    HAS_TERMINAL=$(oc get deploy "${DEPLOY}" -n "${NS}" \
      -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"\n"}{end}' \
      | grep -cx 'terminal' || true)
    if [[ "${HAS_TERMINAL}" != "1" ]]; then
      continue
    fi

    echo "  ${DEPLOY}: set HOME=${HOME_DIR} JAVA_TOOL_OPTIONS MAVEN_OPTS"
    oc set env "deploy/${DEPLOY}" -n "${NS}" -c terminal --overwrite \
      "HOME=${HOME_DIR}" \
      "MAVEN_USER_HOME=${MAVEN_HOME}" \
      "JAVA_TOOL_OPTIONS=${JAVA_TOOL_OPTIONS}" \
      "MAVEN_OPTS=${MAVEN_OPTS}"
  done
  echo "  Done: ${NS}"
done

echo "=== Showroom terminal HOME / Maven repo patch complete ==="
