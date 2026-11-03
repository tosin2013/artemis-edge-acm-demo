#!/usr/bin/env bash
# collect-teardown-evidence.sh — Capture rung 6 (teardown) evidence
# Run this BEFORE and AFTER teardown to capture the before/after diff.
#
# Usage:
#   ./scripts/collect-teardown-evidence.sh --sandbox <SANDBOX> --phase before
#   # ... run teardown ...
#   ./scripts/collect-teardown-evidence.sh --sandbox <SANDBOX> --phase after
#
# Requires: gcloud (authenticated to openenv-<SANDBOX>)

set -euo pipefail

EVIDENCE_DIR="docs/evidence/001-mode2-gcp-deploy/rung6"

SANDBOX=""
PHASE=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --sandbox) SANDBOX="$2"; shift 2 ;;
    --phase) PHASE="$2"; shift 2 ;;
    *) echo "Usage: $0 --sandbox <SANDBOX> --phase <before|after>"; exit 1 ;;
  esac
done

if [[ -z "$SANDBOX" || -z "$PHASE" ]]; then
  echo "Error: --sandbox and --phase are required"
  echo "Usage: $0 --sandbox <SANDBOX> --phase <before|after>"
  exit 1
fi

PROJECT="openenv-${SANDBOX}"
mkdir -p "${EVIDENCE_DIR}"

echo "=== Rung 6 ${PHASE} capture — $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
echo "Project: ${PROJECT}"
echo ""

echo "GCP compute instances:"
gcloud compute instances list --project="${PROJECT}" 2>&1 \
  | tee "${EVIDENCE_DIR}/gcp-instances-${PHASE}.txt"

echo ""
echo "GCP persistent disks:"
gcloud compute disks list --project="${PROJECT}" 2>&1 \
  | tee "${EVIDENCE_DIR}/gcp-disks-${PHASE}.txt"

echo ""
echo "GCP DNS managed zones:"
gcloud dns managed-zones list --project="${PROJECT}" 2>&1 \
  | tee "${EVIDENCE_DIR}/gcp-dns-${PHASE}.txt"

echo ""
echo "GCP VPC networks:"
gcloud compute networks list --project="${PROJECT}" 2>&1 \
  | tee "${EVIDENCE_DIR}/gcp-networks-${PHASE}.txt"

if [[ "$PHASE" == "after" && -f "${EVIDENCE_DIR}/gcp-instances-before.txt" ]]; then
  echo ""
  echo "=== Diff: instances before vs after ==="
  diff "${EVIDENCE_DIR}/gcp-instances-before.txt" \
       "${EVIDENCE_DIR}/gcp-instances-after.txt" \
    | tee "${EVIDENCE_DIR}/diff-instances.txt" || true

  echo ""
  echo "=== Diff: disks before vs after ==="
  diff "${EVIDENCE_DIR}/gcp-disks-before.txt" \
       "${EVIDENCE_DIR}/gcp-disks-after.txt" \
    | tee "${EVIDENCE_DIR}/diff-disks.txt" || true
fi

echo ""
echo "Rung 6 ${PHASE} evidence saved to ${EVIDENCE_DIR}/"
