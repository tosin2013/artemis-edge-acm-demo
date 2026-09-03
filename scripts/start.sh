#!/usr/bin/env bash
set -euo pipefail
#
# Start (resume) a stopped GCP cluster
#
# Usage:
#   ./scripts/start.sh --guid artgcp --account openenv-gcp
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VARS_FILE="${PROJECT_ROOT}/agnosticd/gcp/vars.yml"
SECRETS_DIR="${HOME}/Development/agnosticd-v2-secrets"
AGD_DIR="${HOME}/Development/agnosticd-v2"

: "${AGD_GUID:=artgcp}"
: "${AGD_ACCOUNT:=openenv-gcp}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --guid) AGD_GUID="$2"; shift 2 ;;
    --account) AGD_ACCOUNT="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

SECRETS_FILE="${SECRETS_DIR}/secrets-${AGD_ACCOUNT}.yml"
GCP_KEY_FILE=$(find "${SECRETS_DIR}" -name "gcp-key-*.json" 2>/dev/null | head -1)

echo "=== Artemis Edge ACM Demo — GCP Start ==="
echo "GUID: ${AGD_GUID}"

cd "${AGD_DIR}"

agd start \
  --guid "${AGD_GUID}" \
  -c openshift-cluster \
  -e @"${VARS_FILE}" \
  -e @"${SECRETS_FILE}" \
  -e "gcp_credentials_file=${GCP_KEY_FILE}"
