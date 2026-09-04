#!/usr/bin/env bash
set -euo pipefail
#
# Deploy Artemis Edge ACM Demo on GCP via AgnosticD v2
#
# Uses ansible-playbook directly against the AgnosticD main.yml entrypoint.
#
# Prerequisites:
#   - ansible-playbook installed (ansible-core)
#   - AgnosticD v2 repo cloned to ~/Development/agnosticd-v2
#   - GCP secrets populated (see agnosticd/gcp/secrets.yml.example)
#   - GCP service account JSON key downloaded
#
# Usage:
#   ./scripts/deploy.sh --guid 725j2 --account openenv-gcp
#   ./scripts/deploy.sh  # uses defaults from AGD_GUID / AGD_ACCOUNT env vars
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VARS_FILE="${PROJECT_ROOT}/agnosticd/gcp/vars.yml"
SECRETS_DIR="${HOME}/Development/agnosticd-v2-secrets"
AGD_DIR="${HOME}/Development/agnosticd-v2"
OUTPUT_DIR="${HOME}/Development/agnosticd-v2-output"

: "${AGD_GUID:=artgcp}"
: "${AGD_ACCOUNT:=openenv-gcp}"

# Parse --guid and --account from CLI args
while [[ $# -gt 0 ]]; do
  case $1 in
    --guid) AGD_GUID="$2"; shift 2 ;;
    --account) AGD_ACCOUNT="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

SECRETS_FILE="${SECRETS_DIR}/secrets-${AGD_ACCOUNT}.yml"
GCP_KEY_FILE=$(find "${SECRETS_DIR}" -name "gcp-key-*.json" 2>/dev/null | head -1)
GUID_OUTPUT_DIR="${OUTPUT_DIR}/${AGD_GUID}"

echo "=== Artemis Edge ACM Demo — GCP Deployment ==="
echo "GUID:        ${AGD_GUID}"
echo "Account:     ${AGD_ACCOUNT}"
echo "Vars:        ${VARS_FILE}"
echo "Secrets:     ${SECRETS_FILE}"
echo "GCP Key:     ${GCP_KEY_FILE:-NOT FOUND}"
echo "Output:      ${GUID_OUTPUT_DIR}"
echo ""

# Validate prerequisites
if [[ ! -f "${VARS_FILE}" ]]; then
  echo "ERROR: Vars file not found: ${VARS_FILE}" >&2
  exit 1
fi

if [[ ! -f "${SECRETS_FILE}" ]]; then
  echo "ERROR: Secrets file not found: ${SECRETS_FILE}" >&2
  echo "Copy agnosticd/gcp/secrets.yml.example to ${SECRETS_FILE} and fill in values." >&2
  exit 1
fi

if [[ -z "${GCP_KEY_FILE}" ]]; then
  echo "ERROR: No GCP key file found in ${SECRETS_DIR}/" >&2
  echo "Download the service account key from GCP Console and save as gcp-key-<id>.json" >&2
  exit 1
fi

if [[ ! -d "${AGD_DIR}/ansible" ]]; then
  echo "ERROR: AgnosticD v2 repo not found at ${AGD_DIR}" >&2
  echo "Clone it: git clone https://github.com/redhat-cop/agnosticd.git ${AGD_DIR}" >&2
  exit 1
fi

# Prefer ansible-navigator with EE image (all deps included)
# Fall back to ansible-playbook if navigator not available
USE_NAVIGATOR=false
if command -v ansible-navigator &>/dev/null; then
  USE_NAVIGATOR=true
elif ! command -v ansible-playbook &>/dev/null; then
  echo "ERROR: Neither ansible-navigator nor ansible-playbook found." >&2
  echo "Install: pip3 install --user 'ansible-navigator[ansible-core]'" >&2
  exit 1
fi

mkdir -p "${GUID_OUTPUT_DIR}"

echo "=== Starting provision... ==="
cd "${AGD_DIR}"

if [[ "${USE_NAVIGATOR}" == "true" ]]; then
  echo "Using ansible-navigator with EE image..."
  ansible-navigator run ansible/main.yml \
    --mode stdout \
    --eei quay.io/agnosticd/ee-multicloud:latest \
    --eev "${SECRETS_DIR}:${SECRETS_DIR}" \
    --eev "${GUID_OUTPUT_DIR}:${GUID_OUTPUT_DIR}" \
    -e guid="${AGD_GUID}" \
    -e @"${VARS_FILE}" \
    -e @"${SECRETS_FILE}" \
    -e "gcp_credentials_file=${GCP_KEY_FILE}" \
    -e "output_dir=${GUID_OUTPUT_DIR}"
else
  echo "Using ansible-playbook directly..."
  ansible-playbook ansible/main.yml \
    -e guid="${AGD_GUID}" \
    -e @"${VARS_FILE}" \
    -e @"${SECRETS_FILE}" \
    -e "gcp_credentials_file=${GCP_KEY_FILE}" \
    -e "output_dir=${GUID_OUTPUT_DIR}"
fi

echo ""
echo "=== Provision complete! ==="
echo "Run: ./scripts/save-deployment-info.sh ${AGD_GUID}"
echo "     to populate deployment-info.yml"
