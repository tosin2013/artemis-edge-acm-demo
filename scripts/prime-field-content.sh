#!/usr/bin/env bash
set -euo pipefail
#
# Prime field-content operator subscriptions.
#
# Argo CD discovers every API group in the rendered Helm chart before it
# applies sync waves. SkipDryRunOnMissingResource does not skip that
# discovery, so field-content stays OutOfSync while Keycloak, AMQ, or
# MulticlusterGlobalHub CRDs are absent.
#
# This applies only Namespace, OperatorGroup, and Subscription documents
# from the live Application's Helm values (the same chart that is in git),
# waits until every API group in that render is served, then requests a sync.
# A hard refresh alone does not retry a failed sync of the same revision.
# It does not apply custom resources.
#
# Usage:
#   ./scripts/prime-field-content.sh --sandbox <SANDBOX_ID>
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${AGD_OUTPUT_DIR:-${HOME}/Development/agnosticd-v2-output}"
SANDBOX=""
TIMEOUT=900
POLL_INTERVAL=20

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sandbox)     SANDBOX="$2"; shift 2 ;;
    --output-dir)  OUTPUT_DIR="$2"; shift 2 ;;
    --timeout)     TIMEOUT="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 --sandbox <SANDBOX_ID> [--output-dir DIR] [--timeout SECONDS]"
      exit 0
      ;;
    *) echo "ERROR: Unknown option '$1'" >&2; exit 1 ;;
  esac
done

if [[ -z "$SANDBOX" ]]; then
  echo "ERROR: --sandbox is required." >&2
  exit 1
fi
if ! command -v helm >/dev/null 2>&1; then
  echo "ERROR: helm is required." >&2
  exit 1
fi
if ! python3 -c 'import yaml' >/dev/null 2>&1; then
  echo "ERROR: python3 PyYAML is required." >&2
  exit 1
fi

WORKDIR="$(mktemp -d)"
chmod 700 "$WORKDIR"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

echo "=== Prime field-content operators — Sandbox: ${SANDBOX} ==="

declare -A KUBECONFIGS
for token in global east cen west; do
  kc="${OUTPUT_DIR}/${token}-${SANDBOX}/openshift-cluster_${token}-${SANDBOX}_kubeconfig"
  if [[ -f "$kc" ]]; then
    KUBECONFIGS["${token}-${SANDBOX}"]="$kc"
  else
    echo "  [SKIP] ${token}-${SANDBOX}: kubeconfig not found"
  fi
done

if [[ ${#KUBECONFIGS[@]} -eq 0 ]]; then
  echo "ERROR: no kubeconfigs found under ${OUTPUT_DIR}" >&2
  exit 1
fi

failed=0
for hub_id in "${!KUBECONFIGS[@]}"; do
  kc="${KUBECONFIGS[$hub_id]}"
  hub_dir="${WORKDIR}/${hub_id}"
  mkdir -p "$hub_dir"
  chmod 700 "$hub_dir"

  if ! KUBECONFIG="$kc" oc get applications.argoproj.io field-content -n openshift-gitops >/dev/null 2>&1; then
    echo "  [SKIP] ${hub_id}: no field-content Application"
    continue
  fi

  KUBECONFIG="$kc" oc get applications.argoproj.io field-content -n openshift-gitops \
    -o jsonpath='{.spec.source.helm.values}' > "${hub_dir}/values.yaml"
  chmod 600 "${hub_dir}/values.yaml"
  if [[ ! -s "${hub_dir}/values.yaml" ]]; then
    echo "  [SKIP] ${hub_id}: field-content has no Helm values"
    continue
  fi

  if ! helm template field-content "$CHART_DIR" -f "${hub_dir}/values.yaml" > "${hub_dir}/render.yaml" 2>"${hub_dir}/helm.err"; then
    echo "  [FAIL] ${hub_id}: helm template failed"
    sed 's/^/    /' "${hub_dir}/helm.err"
    failed=1
    continue
  fi

  prime_count="$(python3 - "${hub_dir}/render.yaml" "${hub_dir}/prime.yaml" <<'PY'
import sys, yaml
src, dst = sys.argv[1], sys.argv[2]
keep = {"Namespace", "OperatorGroup", "Subscription"}
order = {"Namespace": 0, "OperatorGroup": 1, "Subscription": 2}
docs = []
for doc in yaml.safe_load_all(open(src)):
    if isinstance(doc, dict) and doc.get("kind") in keep and doc.get("metadata", {}).get("name"):
        docs.append(doc)
docs.sort(key=lambda d: (order[d["kind"]], d["metadata"]["name"]))
with open(dst, "w") as out:
    yaml.safe_dump_all(docs, out)
print(len(docs))
PY
)"
  echo "  [APPLY] ${hub_id}: ${prime_count} Namespace/OperatorGroup/Subscription objects"
  if ! KUBECONFIG="$kc" oc apply -f "${hub_dir}/prime.yaml"; then
    echo "  [FAIL] ${hub_id}: oc apply failed"
    failed=1
    continue
  fi
  echo "$kc" > "${hub_dir}/kubeconfig.path"
done

echo ""
echo "--- Waiting for rendered API groups (timeout ${TIMEOUT}s) ---"
deadline=$((SECONDS + TIMEOUT))
pending=1
while [[ "$pending" -eq 1 ]]; do
  pending=0
  for hub_id in "${!KUBECONFIGS[@]}"; do
    hub_dir="${WORKDIR}/${hub_id}"
    [[ -f "${hub_dir}/render.yaml" && -f "${hub_dir}/kubeconfig.path" ]] || continue
    kc="$(cat "${hub_dir}/kubeconfig.path")"
    if [[ -f "${hub_dir}/ready" ]]; then
      continue
    fi
    KUBECONFIG="$kc" oc api-versions > "${hub_dir}/apiversions.txt" 2>/dev/null || true
    missing="$(python3 - "${hub_dir}/render.yaml" "${hub_dir}/apiversions.txt" <<'PY'
import sys, yaml
render, served_path = sys.argv[1], sys.argv[2]
served = set(open(served_path).read().split())
need = set()
for doc in yaml.safe_load_all(open(render)):
    if isinstance(doc, dict) and doc.get("apiVersion"):
        need.add(doc["apiVersion"])
missing = sorted(a for a in need if a not in served)
print(" ".join(missing))
PY
)"
    if [[ -z "$missing" ]]; then
      echo "  [OK]   ${hub_id}: API groups served"
      touch "${hub_dir}/ready"
      # A hard refresh does not retry a failed sync of the same revision.
      # Automated sync also stays idle after that failure, so request one.
      KUBECONFIG="$kc" oc patch applications.argoproj.io field-content -n openshift-gitops --type merge \
        -p '{"spec":{"syncPolicy":{"retry":{"limit":5,"backoff":{"duration":"10s","factor":2,"maxDuration":"3m"}}}}}' \
        >/dev/null 2>&1 || true
      if KUBECONFIG="$kc" oc patch applications.argoproj.io field-content -n openshift-gitops --type merge \
        -p '{"operation":{"initiatedBy":{"username":"prime-field-content"},"sync":{"revision":"main"}}}' \
        >/dev/null 2>&1; then
        echo "  [SYNC] ${hub_id}: requested field-content sync"
      else
        echo "  [WARN] ${hub_id}: could not request a sync (one may already be running)"
      fi
    else
      pending=1
      echo "  [WAIT] ${hub_id}: ${missing}"
    fi
  done
  if [[ "$pending" -eq 0 ]]; then
    break
  fi
  if (( SECONDS >= deadline )); then
    echo "  [FAIL] timed out waiting for API groups"
    failed=1
    break
  fi
  sleep "$POLL_INTERVAL"
done

echo ""
if [[ "$failed" -ne 0 ]]; then
  echo "=== Prime field-content operators failed ==="
  exit 1
fi
echo "=== Prime field-content operators complete ==="
