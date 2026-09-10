#!/usr/bin/env bash
set -euo pipefail
#
# Deploy / Destroy / Lifecycle Artemis Edge ACM Demo via agd CLI
#
# This is the project entry point that delegates to the agd CLI from
# tosin2013/agnosticd-v2. It reads config.yml for defaults and passes
# execution to: ./bin/agd <action> -g <GUID> -c artemis-edge-gcp -a <ACCOUNT>
#
# Prerequisites:
#   - AgnosticD v2 cloned with agd setup completed
#   - GCP secrets populated in agnosticd-v2-secrets/
#   - Vars file copied to agnosticd-v2-vars/artemis-edge-gcp.yml
#
# Usage:
#   ./scripts/deploy.sh --guid 725j2 --account openenv-gcp
#   ./scripts/deploy.sh --mode multi-hub --guid 725j2 --account openenv-gcp
#   ./scripts/deploy.sh --destroy --guid 725j2 --account openenv-gcp
#   ./scripts/deploy.sh --stop --guid 725j2 --account openenv-gcp
#   ./scripts/deploy.sh --start --guid 725j2 --account openenv-gcp
#   ./scripts/deploy.sh --status --guid 725j2 --account openenv-gcp
#   ./scripts/deploy.sh  # reads GUID and mode from config.yml or env vars
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# AgnosticD v2 directory (where bin/agd lives)
AGD_ROOT="${AGD_ROOT:-${HOME}/Development/agnosticd-v2}"

# Config name used by agd to find the vars file in agnosticd-v2-vars/
# Overridden below when --mode multi-hub is selected.
AGD_CONFIG="artemis-edge-gcp"

# Deployment mode: single-hub (default) or multi-hub
# Read from config.yml if not set via env or CLI
: "${DEPLOY_MODE:=}"
if [[ -z "${DEPLOY_MODE}" && -f "${PROJECT_ROOT}/config.yml" ]]; then
  DEPLOY_MODE=$(python3 -c "import yaml; print(yaml.safe_load(open('${PROJECT_ROOT}/config.yml')).get('mode','single-hub'))" 2>/dev/null) || true
fi
: "${DEPLOY_MODE:=single-hub}"

# Read GUID from config.yml if not set via env or CLI
if [[ -z "${AGD_GUID:-}" && -f "${PROJECT_ROOT}/config.yml" ]]; then
  AGD_GUID=$(python3 -c "import yaml; print(yaml.safe_load(open('${PROJECT_ROOT}/config.yml'))['agd_guid'])" 2>/dev/null) || true
fi
: "${AGD_GUID:=}"
: "${AGD_ACCOUNT:=openenv-gcp}"
: "${AGD_ACTION:=provision}"

# Parse CLI args
while [[ $# -gt 0 ]]; do
  case $1 in
    --guid) AGD_GUID="$2"; shift 2 ;;
    --account) AGD_ACCOUNT="$2"; shift 2 ;;
    --action) AGD_ACTION="$2"; shift 2 ;;
    --mode) DEPLOY_MODE="$2"; shift 2 ;;
    --destroy) AGD_ACTION="destroy"; shift ;;
    --stop) AGD_ACTION="stop"; shift ;;
    --start) AGD_ACTION="start"; shift ;;
    --status) AGD_ACTION="status"; shift ;;
    --validate) AGD_ACTION="validate-deployment"; shift ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --guid GUID        Deployment GUID (reads from config.yml if not set)"
      echo "  --account ACCOUNT  Secrets account name (default: openenv-gcp)"
      echo "  --mode MODE        Deployment mode: single-hub (default) or multi-hub"
      echo "  --action ACTION    AgnosticD action: provision, destroy, stop, start, status"
      echo "  --destroy          Shorthand for --action destroy"
      echo "  --stop             Shorthand for --action stop"
      echo "  --start            Shorthand for --action start"
      echo "  --status           Shorthand for --action status"
      echo "  --validate         Run post-deploy validation checks"
      echo "  -h, --help         Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0 --guid 725j2 --account openenv-gcp"
      echo "  $0 --mode multi-hub --guid 725j2 --account openenv-gcp"
      echo "  $0 --destroy --guid 725j2"
      echo "  $0  # reads GUID and mode from config.yml"
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; echo "Use --help for usage." >&2; exit 1 ;;
  esac
done

# Require GUID
if [[ -z "${AGD_GUID}" ]]; then
  echo "ERROR: GUID required. Use --guid <id>, set AGD_GUID, or run bootstrap.sh first." >&2
  exit 1
fi

# Resolve deployment mode → agd config name
case "${DEPLOY_MODE}" in
  single-hub)
    AGD_CONFIG="artemis-edge-gcp"
    ;;
  multi-hub)
    AGD_CONFIG="artemis-edge-gcp-multihub"
    ;;
  *)
    echo "ERROR: Unknown mode '${DEPLOY_MODE}'. Use: single-hub, multi-hub" >&2
    exit 1
    ;;
esac

# Validate agd is available
if [[ ! -x "${AGD_ROOT}/bin/agd" ]]; then
  echo "ERROR: agd CLI not found at ${AGD_ROOT}/bin/agd" >&2
  echo "Clone AgnosticD v2: git clone https://github.com/tosin2013/agnosticd-v2.git ${AGD_ROOT}" >&2
  echo "Then run: cd ${AGD_ROOT} && ./bin/agd setup" >&2
  exit 1
fi

# Validate action
case "${AGD_ACTION}" in
  provision|destroy|stop|start|status) ;;
  validate-deployment)
    echo "=== Artemis Edge ACM Demo — Post-Deploy Validation ==="
    KUBECONFIG_FILE="${AGD_ROOT}/../agnosticd-v2-output/${AGD_GUID}/openshift-cluster_${AGD_GUID}_kubeconfig"
    if [[ -f "$KUBECONFIG_FILE" ]]; then
      exec "${SCRIPT_DIR}/validate-deployment.sh" --kubeconfig "$KUBECONFIG_FILE"
    else
      echo "WARN: kubeconfig not found at ${KUBECONFIG_FILE}, using current KUBECONFIG"
      exec "${SCRIPT_DIR}/validate-deployment.sh"
    fi
    ;;
  *) echo "ERROR: Unknown action '${AGD_ACTION}'. Use: provision, destroy, stop, start, status, validate-deployment" >&2; exit 1 ;;
esac

echo "=== Artemis Edge ACM Demo — ${AGD_ACTION^} ==="
echo "Action:      ${AGD_ACTION}"
echo "Mode:        ${DEPLOY_MODE}"
echo "GUID:        ${AGD_GUID}"
echo "Config:      ${AGD_CONFIG}"
echo "Account:     ${AGD_ACCOUNT}"
echo "AgnosticD:   ${AGD_ROOT}"
echo ""

# Activate virtualenv if it exists (agd needs ansible-navigator from the venv)
VENV_DIR="${AGD_ROOT}/../agnosticd-v2-virtualenv"
if [[ -d "${VENV_DIR}" ]]; then
  source "${VENV_DIR}/bin/activate" 2>/dev/null || true
fi

# Delegate to agd
echo "=== Delegating to agd ${AGD_ACTION}... ==="
cd "${AGD_ROOT}"

if [[ "${AGD_ACTION}" == "provision" ]]; then
  ./bin/agd "${AGD_ACTION}" -g "${AGD_GUID}" -c "${AGD_CONFIG}" -a "${AGD_ACCOUNT}"
  AGD_EXIT=$?
  echo ""
  echo "=== Saving deployment info... ==="
  "${SCRIPT_DIR}/save-deployment-info.sh" "${AGD_GUID}" || echo "WARN: save-deployment-info.sh failed (non-fatal)"
  echo ""
  echo "=== Patching Showroom for deployment mode... ==="
  KUBECONFIG_FILE="${AGD_ROOT}/../agnosticd-v2-output/${AGD_GUID}/openshift-cluster_${AGD_GUID}_kubeconfig"
  "${SCRIPT_DIR}/patch-showroom-mode.sh" "${AGD_GUID}" "${DEPLOY_MODE}" "${KUBECONFIG_FILE}" \
    || echo "WARN: patch-showroom-mode.sh failed (non-fatal)"
  echo ""
  echo "=== Patching Showroom terminal HOME for Maven... ==="
  "${SCRIPT_DIR}/patch-showroom-home.sh" "${AGD_GUID}" "${KUBECONFIG_FILE}" \
    || echo "WARN: patch-showroom-home.sh failed (non-fatal)"
  exit $AGD_EXIT
else
  exec ./bin/agd "${AGD_ACTION}" -g "${AGD_GUID}" -c "${AGD_CONFIG}" -a "${AGD_ACCOUNT}"
fi
