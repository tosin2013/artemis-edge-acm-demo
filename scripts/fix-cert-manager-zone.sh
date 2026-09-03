#!/usr/bin/env bash
set -euo pipefail
#
# Fix cert-manager ClusterIssuer GCP zone name and reissue certificates.
#
# The upstream core_workloads cert-manager template hardcodes
# hostedZoneName: dns-zone-{{ guid }}, but GCP Open Environments
# use dns-zone-{sandbox-id} (e.g. dns-zone-8lqmc).
#
# This script:
#   1. Patches the ClusterIssuer with the correct zone name
#   2. Cleans up stale challenges from the failed attempt
#   3. Recreates the ingress certificate
#   4. Waits for it to become Ready
#   5. Patches the IngressController to use the new cert
#
# Usage:
#   export KUBECONFIG=/path/to/kubeconfig
#   ./scripts/fix-cert-manager-zone.sh <base_domain>
#
# Example:
#   ./scripts/fix-cert-manager-zone.sh 8lqmc.gcp.redhatworkshops.io

BASE_DOMAIN="${1:?Usage: $0 <base_domain>}"
ZONE_ID="${BASE_DOMAIN%%.*}"
ZONE_NAME="dns-zone-${ZONE_ID}"
ISSUER_NAME="letsencrypt-production-gcp"
WILDCARD_DOMAIN="*.apps.hub.${BASE_DOMAIN}"

echo "==> Zone name: ${ZONE_NAME}"
echo "==> Wildcard:  ${WILDCARD_DOMAIN}"

if ! oc get clusterissuer "${ISSUER_NAME}" &>/dev/null; then
  echo "ERROR: ClusterIssuer ${ISSUER_NAME} not found. Is cert-manager deployed?" >&2
  exit 1
fi

echo "==> Patching ClusterIssuer ${ISSUER_NAME} with hostedZoneName=${ZONE_NAME}"
oc patch clusterissuer "${ISSUER_NAME}" --type=json \
  -p "[{\"op\":\"replace\",\"path\":\"/spec/acme/solvers/0/dns01/cloudDNS/hostedZoneName\",\"value\":\"${ZONE_NAME}\"}]"

echo "==> Cleaning up stale challenges"
for ns in openshift-ingress openshift-config; do
  for ch in $(oc get challenges -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    echo "    Removing challenge ${ch} in ${ns}"
    oc patch challenge "$ch" -n "$ns" --type=json \
      -p '[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true
    oc delete challenge "$ch" -n "$ns" 2>/dev/null || true
  done
done

echo "==> Deleting existing certificates"
oc delete certificate cert-manager-ingress-cert -n openshift-ingress 2>/dev/null || true
oc delete certificate cert-manager-api-cert -n openshift-config 2>/dev/null || true

echo "==> Creating fresh ingress certificate"
cat <<EOF | oc apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: cert-manager-ingress-cert
  namespace: openshift-ingress
spec:
  secretName: cert-manager-ingress-cert
  issuerRef:
    name: ${ISSUER_NAME}
    kind: ClusterIssuer
  dnsNames:
    - "${WILDCARD_DOMAIN}"
EOF

echo "==> Waiting for certificate (up to 10 minutes)..."
for i in $(seq 1 30); do
  READY=$(oc get certificate cert-manager-ingress-cert -n openshift-ingress \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
  if [ "$READY" = "True" ]; then
    echo "==> Certificate is Ready!"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "ERROR: Certificate not ready after 10 minutes." >&2
    oc get certificate -n openshift-ingress
    oc get challenges -n openshift-ingress 2>/dev/null
    exit 1
  fi
  sleep 20
done

CURRENT=$(oc get ingresscontroller default -n openshift-ingress-operator \
  -o jsonpath='{.spec.defaultCertificate.name}' 2>/dev/null || echo "")
if [ "$CURRENT" != "cert-manager-ingress-cert" ]; then
  echo "==> Patching IngressController to use the new certificate"
  oc patch ingresscontroller default -n openshift-ingress-operator \
    --type=merge -p '{"spec":{"defaultCertificate":{"name":"cert-manager-ingress-cert"}}}'
fi

echo "==> Done. Verifying TLS..."
sleep 10
echo | openssl s_client -connect "console-openshift-console.apps.hub.${BASE_DOMAIN}:443" \
  -servername "console-openshift-console.apps.hub.${BASE_DOMAIN}" 2>/dev/null \
  | openssl x509 -noout -issuer -subject -dates 2>&1 || echo "(TLS check skipped — may need more time for router rollout)"
