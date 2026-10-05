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
#   ./scripts/deploy.sh --mode multi-hub --tier global --sandbox abc12 --account openenv-gcp
#   ./scripts/deploy.sh --mode multi-hub --tier east --sandbox abc12
#   ./scripts/deploy.sh --destroy --guid 725j2 --account openenv-gcp
#   ./scripts/deploy.sh --stop --guid 725j2 --account openenv-gcp
#   ./scripts/deploy.sh --start --guid 725j2 --account openenv-gcp
#   ./scripts/deploy.sh --status --guid 725j2 --account openenv-gcp
#   ./scripts/deploy.sh  # reads GUID and mode from config.yml or env vars
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# AgnosticD v2 directory (where bin/agd lives)
# Priority: $AGD_ROOT env var > config.yml agnosticd_root > default path
if [[ -z "${AGD_ROOT:-}" && -f "${PROJECT_ROOT}/config.yml" ]]; then
  AGD_ROOT=$(python3 -c "import yaml; print(yaml.safe_load(open('${PROJECT_ROOT}/config.yml')).get('agnosticd_root',''))" 2>/dev/null) || true
fi
AGD_ROOT="${AGD_ROOT:-${HOME}/Development/agnosticd-v2}"
# Expand ~ if present (config.yml may store ~/Development/...)
AGD_ROOT="${AGD_ROOT/#\~/$HOME}"

# Config name used by agd to find the vars file in agnosticd-v2-vars/
# Overridden below when --mode multi-hub is selected.
AGD_CONFIG="artemis-edge-gcp"

# Mode 2 hub tier: global (default), east, central, west. regional aliases east.
# See agnosticd/gcp/MODE2.md
: "${HUB_TIER:=global}"
: "${SANDBOX:=}"

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
    --sandbox) SANDBOX="$2"; shift 2 ;;
    --account) AGD_ACCOUNT="$2"; shift 2 ;;
    --action) AGD_ACTION="$2"; shift 2 ;;
    --mode) DEPLOY_MODE="$2"; shift 2 ;;
    --tier) HUB_TIER="$2"; shift 2 ;;
    --destroy) AGD_ACTION="destroy"; shift ;;
    --stop) AGD_ACTION="stop"; shift ;;
    --start) AGD_ACTION="start"; shift ;;
    --status) AGD_ACTION="status"; shift ;;
    --validate) AGD_ACTION="validate-deployment"; shift ;;
    --finalize) AGD_ACTION="finalize"; shift ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --guid GUID        Mode 1: OpenEnv sandbox. Mode 2: sandbox if --sandbox omitted"
      echo "  --sandbox ID      Mode 2: OpenEnv sandbox (5-char). agd GUID becomes {region}-{sandbox} (cen not central)"
      echo "  --account ACCOUNT  Secrets account name (default: openenv-gcp)"
      echo "  --mode MODE        Deployment mode: single-hub (default) or multi-hub"
      echo "  --tier TIER        Mode 2: global (default), east, central, west, all (sequential)"
      echo "  --action ACTION    AgnosticD action: provision, destroy, stop, start, status"
      echo "  --destroy          Shorthand for --action destroy"
      echo "  --stop             Shorthand for --action stop"
      echo "  --start            Shorthand for --action start"
      echo "  --status           Shorthand for --action status"
      echo "  --validate         Run post-deploy validation checks"
      echo "  --finalize         Mode 2: import hubs + patch workarounds (auto-runs when last tier provisions)"
      echo "  -h, --help         Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0 --guid 725j2 --account openenv-gcp"
      echo "  $0 --mode multi-hub --tier all --sandbox abc12 --account openenv-gcp"
      echo "  $0 --mode multi-hub --tier global --sandbox abc12 --account openenv-gcp"
      echo "  $0 --mode multi-hub --tier east --sandbox abc12 --account openenv-gcp"
      echo "  $0 --destroy --guid 725j2"
      echo "  $0  # reads GUID and mode from config.yml"
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; echo "Use --help for usage." >&2; exit 1 ;;
  esac
done

# Mode 2: one OpenEnv sandbox; agd GUID is {region}-{sandbox} so output_dir
# and bastion-{{ guid }} do not collide. hub-{tier}-{sandbox} exceeds systemd's
# 64-character hostname (bastion-{{ guid }}.{{ guid }}.{{ base_domain }}).
# Central token is cen: central-{sandbox} FQDN is 65 characters.
# Secrets stay on openenv-${SANDBOX}.
if [[ "${DEPLOY_MODE}" == "multi-hub" ]]; then
  # --tier all: provision all 4 tiers sequentially (global → east → central → west)
  if [[ "${HUB_TIER}" == "all" ]]; then
    _SANDBOX="${SANDBOX:-${AGD_GUID}}"
    if [[ -z "${_SANDBOX}" ]]; then
      echo "ERROR: --tier all needs --sandbox <OpenEnv id> (or --guid as sandbox)." >&2
      exit 1
    fi
    echo "============================================================"
    echo "  Mode 2 — Sequential provisioning of all 4 tiers"
    echo "  Sandbox: ${_SANDBOX}  |  Action: ${AGD_ACTION}"
    echo "  Order: global → east → central → west"
    echo "============================================================"
    echo ""
    _ALL_EXIT=0
    for _tier in global east central west; do
      echo ">>> Tier: ${_tier} ($(date '+%H:%M:%S')) ..."
      "$0" --mode multi-hub --tier "${_tier}" --sandbox "${_SANDBOX}" \
           --account "${AGD_ACCOUNT}" --action "${AGD_ACTION}" || {
        _ALL_EXIT=$?
        echo ""
        echo "ERROR: Tier '${_tier}' failed (exit ${_ALL_EXIT})."
        echo "Fix the issue, then resume from the failed tier:"
        echo "  $0 --mode multi-hub --tier ${_tier} --sandbox ${_SANDBOX} --account ${AGD_ACCOUNT}"
        echo "Or re-run all remaining tiers from '${_tier}'."
        exit ${_ALL_EXIT}
      }
      echo ">>> Tier ${_tier} complete ($(date '+%H:%M:%S'))"
      echo ""
    done
    echo "============================================================"
    echo "  All 4 tiers provisioned successfully!"
    echo "============================================================"
    exit 0
  fi

  if [[ "${HUB_TIER}" == "regional" ]]; then
    HUB_TIER="east"
  fi
  SANDBOX="${SANDBOX:-${AGD_GUID}}"
  if [[ -z "${SANDBOX}" ]]; then
    echo "ERROR: Mode 2 needs --sandbox <OpenEnv id> (or --guid / config.yml agd_guid as the sandbox)." >&2
    exit 1
  fi
  if [[ ! "${SANDBOX}" =~ ^[a-z0-9]{5}$ ]]; then
    echo "ERROR: sandbox '${SANDBOX}' is not a 5-character OpenEnv id." >&2
    echo "Pass --sandbox abc12, not a composed agd GUID like east-abc12." >&2
    exit 1
  fi
  case "${HUB_TIER}" in
    global) TIER_TOKEN="global" ;;
    east) TIER_TOKEN="east" ;;
    central) TIER_TOKEN="cen" ;;
    west) TIER_TOKEN="west" ;;
    *)
      echo "ERROR: Unknown --tier '${HUB_TIER}'. Use: global, east, central, west (regional aliases east)" >&2
      exit 1
      ;;
  esac
  AGD_GUID="${TIER_TOKEN}-${SANDBOX}"
elif [[ -n "${SANDBOX}" ]]; then
  echo "ERROR: --sandbox is Mode 2 only. For Mode 1 use --guid <sandbox>." >&2
  exit 1
fi

# Require GUID
if [[ -z "${AGD_GUID}" ]]; then
  echo "ERROR: GUID required. Use --guid <id>, --sandbox <id> (Mode 2), set AGD_GUID, or run bootstrap.sh first." >&2
  exit 1
fi

# Resolve deployment mode → agd config name
case "${DEPLOY_MODE}" in
  single-hub)
    AGD_CONFIG="artemis-edge-gcp"
    ;;
  multi-hub)
    case "${HUB_TIER}" in
      global) AGD_CONFIG="artemis-edge-gcp-multihub" ;;
      east) AGD_CONFIG="artemis-edge-gcp-multihub-regional" ;;
      central) AGD_CONFIG="artemis-edge-gcp-multihub-central" ;;
      west) AGD_CONFIG="artemis-edge-gcp-multihub-west" ;;
      *)
        echo "ERROR: Unknown --tier '${HUB_TIER}'. Use: global, east, central, west (regional aliases east)" >&2
        exit 1
        ;;
    esac
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
  finalize)
    if [[ "${DEPLOY_MODE}" != "multi-hub" ]]; then
      echo "ERROR: --finalize is only for multi-hub mode." >&2
      exit 1
    fi
    echo "=== Artemis Edge ACM Demo — Post-Provision Finalize ==="
    exec "${SCRIPT_DIR}/post-provision-multihub.sh" --sandbox "${SANDBOX}"
    ;;
  validate-deployment)
    echo "=== Artemis Edge ACM Demo — Post-Deploy Validation ==="
    KUBECONFIG_FILE="${AGD_ROOT}/../agnosticd-v2-output/${AGD_GUID}/openshift-cluster_${AGD_GUID}_kubeconfig"
    if [[ -f "$KUBECONFIG_FILE" ]]; then
      exec "${SCRIPT_DIR}/validate-deployment.sh" --kubeconfig "$KUBECONFIG_FILE" --mode "${DEPLOY_MODE}"
    else
      echo "WARN: kubeconfig not found at ${KUBECONFIG_FILE}, using current KUBECONFIG"
      exec "${SCRIPT_DIR}/validate-deployment.sh" --mode "${DEPLOY_MODE}"
    fi
    ;;
  *) echo "ERROR: Unknown action '${AGD_ACTION}'. Use: provision, destroy, stop, start, status, validate-deployment" >&2; exit 1 ;;
esac

echo "=== Artemis Edge ACM Demo — ${AGD_ACTION^} ==="
echo "Action:      ${AGD_ACTION}"
echo "Mode:        ${DEPLOY_MODE}"
echo "Hub tier:    ${HUB_TIER}"
if [[ "${DEPLOY_MODE}" == "multi-hub" ]]; then
  echo "Sandbox:     ${SANDBOX}"
fi
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

  # Mode 2 cert-manager zone fix + retry
  # The upstream cert-manager template hardcodes dns-zone-{{ guid }}, but the
  # GCP Cloud DNS zone is dns-zone-{sandbox}. When guid is a composite like
  # east-sbhtd, the template produces dns-zone-east-sbhtd (wrong). If provision
  # failed and a kubeconfig exists, fix the zone and re-run provision.
  if [[ $AGD_EXIT -ne 0 && "${DEPLOY_MODE}" == "multi-hub" ]]; then
    KUBECONFIG_FILE="${AGD_ROOT}/../agnosticd-v2-output/${AGD_GUID}/openshift-cluster_${AGD_GUID}_kubeconfig"
    if [[ -f "$KUBECONFIG_FILE" ]]; then
      CURRENT_ZONE=$(KUBECONFIG="$KUBECONFIG_FILE" oc get clusterissuer letsencrypt-production-gcp \
        -o jsonpath='{.spec.acme.solvers[0].dns01.cloudDNS.hostedZoneName}' 2>/dev/null || true)
      CORRECT_ZONE="dns-zone-${SANDBOX}"
      if [[ -n "$CURRENT_ZONE" && "$CURRENT_ZONE" != "$CORRECT_ZONE" ]]; then
        echo ""
        echo "=== Cert-manager zone mismatch detected: ${CURRENT_ZONE} != ${CORRECT_ZONE} ==="
        echo "    Applying fix and retrying provision..."
        echo ""

        # Patch ClusterIssuer with correct zone
        KUBECONFIG="$KUBECONFIG_FILE" oc patch clusterissuer letsencrypt-production-gcp --type=json \
          -p "[{\"op\":\"replace\",\"path\":\"/spec/acme/solvers/0/dns01/cloudDNS/hostedZoneName\",\"value\":\"${CORRECT_ZONE}\"}]" \
          2>&1 || true

        # Remove stale challenges (patch off finalizers so they can be deleted)
        for _ns in openshift-ingress openshift-config; do
          for _ch in $(KUBECONFIG="$KUBECONFIG_FILE" oc get challenges -n "$_ns" \
              -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
            KUBECONFIG="$KUBECONFIG_FILE" oc patch challenge "$_ch" -n "$_ns" \
              --type=merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
          done
        done

        # Delete stale certificates so they are recreated with the correct zone
        KUBECONFIG="$KUBECONFIG_FILE" oc delete certificates -A --all 2>/dev/null || true
        KUBECONFIG="$KUBECONFIG_FILE" oc delete certificaterequests -A --all 2>/dev/null || true
        KUBECONFIG="$KUBECONFIG_FILE" oc delete orders -A --all 2>/dev/null || true
        KUBECONFIG="$KUBECONFIG_FILE" oc delete challenges -A --all 2>/dev/null || true
        sleep 10

        echo ""
        echo "=== Retrying agd provision (idempotent — resumes from failed step)... ==="
        ./bin/agd "${AGD_ACTION}" -g "${AGD_GUID}" -c "${AGD_CONFIG}" -a "${AGD_ACCOUNT}"
        AGD_EXIT=$?
      fi
    fi
  fi

  echo ""
  echo "=== Saving deployment info... ==="
  if [[ "${DEPLOY_MODE}" == "multi-hub" ]]; then
    "${SCRIPT_DIR}/save-deployment-info.sh" --mode multi-hub --sandbox "${SANDBOX}" \
      || echo "WARN: save-deployment-info.sh failed (non-fatal)"
  else
    "${SCRIPT_DIR}/save-deployment-info.sh" "${AGD_GUID}" \
      || echo "WARN: save-deployment-info.sh failed (non-fatal)"
  fi
  echo ""
  echo "=== Patching Showroom for deployment mode... ==="
  KUBECONFIG_FILE="${AGD_ROOT}/../agnosticd-v2-output/${AGD_GUID}/openshift-cluster_${AGD_GUID}_kubeconfig"
  "${SCRIPT_DIR}/patch-showroom-mode.sh" "${AGD_GUID}" "${DEPLOY_MODE}" "${KUBECONFIG_FILE}" \
    || echo "WARN: patch-showroom-mode.sh failed (non-fatal)"
  echo ""
  echo "=== Patching Showroom terminal HOME for Maven... ==="
  "${SCRIPT_DIR}/patch-showroom-home.sh" "${AGD_GUID}" "${KUBECONFIG_FILE}" \
    || echo "WARN: patch-showroom-home.sh failed (non-fatal)"

  # Mode 2: auto-finalize when all 4 tiers are provisioned
  if [[ "${DEPLOY_MODE}" == "multi-hub" ]]; then
    echo ""
    echo "=== Checking if all Mode 2 tiers are provisioned... ==="
    AGD_OUTPUT="${AGD_ROOT}/../agnosticd-v2-output"
    ALL_READY=true
    for _token in global east cen west; do
      _kc="${AGD_OUTPUT}/${_token}-${SANDBOX}/openshift-cluster_${_token}-${SANDBOX}_kubeconfig"
      if [[ ! -f "$_kc" ]]; then
        ALL_READY=false
        echo "  Waiting on: ${_token}-${SANDBOX} (kubeconfig not found)"
      fi
    done

    if $ALL_READY; then
      echo "  All 4 tiers provisioned — running post-provision finalize..."
      echo ""
      "${SCRIPT_DIR}/post-provision-multihub.sh" --sandbox "${SANDBOX}" \
        || echo "WARN: post-provision-multihub.sh failed (non-fatal)"
    else
      echo "  Not all tiers ready yet. When all 4 are done, run:"
      echo "    ./scripts/post-provision-multihub.sh --sandbox ${SANDBOX}"
    fi
  fi

  exit $AGD_EXIT
else
  exec ./bin/agd "${AGD_ACTION}" -g "${AGD_GUID}" -c "${AGD_CONFIG}" -a "${AGD_ACCOUNT}"
fi
