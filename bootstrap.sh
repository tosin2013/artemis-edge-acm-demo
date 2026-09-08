#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.yml"
AGD_DIR="${HOME}/Development/agnosticd-v2"
SECRETS_DIR="${HOME}/Development/agnosticd-v2-secrets"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }

# Read default values from onboard.yml (single source of truth)
get_manifest_default() {
  local key="$1" fallback="$2"
  python3 -c "
import yaml
m = yaml.safe_load(open('${SCRIPT_DIR}/onboard.yml'))
for p in m.get('config',{}).get('prompts',[]):
    if p.get('key') == '$key':
        print(p.get('default','$fallback'))
        break
else:
    print('$fallback')
" 2>/dev/null || echo "$fallback"
}

echo "============================================"
echo "  Artemis Edge ACM Demo -- Bootstrap"
echo "============================================"
echo ""

# ===================================================================
# Phase 1: Prerequisites
# ===================================================================
echo "Checking prerequisites..."
MISSING=0

check_prereq() {
  local name="$1" cmd="$2"
  if eval "$cmd" >/dev/null 2>&1; then
    pass "$name"
  else
    fail "$name -- install required"
    MISSING=$((MISSING + 1))
  fi
}

check_prereq "oc"      "oc version --client"
check_prereq "helm"    "helm version --short"
check_prereq "keytool" "keytool 2>&1 | head -1"
check_prereq "java"    "java -version"
check_prereq "mvn"     "mvn -version"
check_prereq "podman"  "podman --version"
check_prereq "git"     "git --version"
check_prereq "jq"      "jq --version"
check_prereq "ansible-navigator" "ansible-navigator --version"

if [ "$MISSING" -gt 0 ]; then
  fail "$MISSING prerequisites missing. Install them and re-run."
  exit 1
fi
echo ""

# ===================================================================
# Phase 2: Configuration
# ===================================================================
if [ ! -f "$CONFIG_FILE" ]; then
  echo "No config.yml found. Let's configure the demo."
  echo ""

  read -rp "Deployment mode [single-hub/multi-hub] (single-hub): " MODE
  MODE="${MODE:-single-hub}"

  read -rp "Cloud provider [gcp/azure] (gcp): " CLOUD
  CLOUD="${CLOUD:-gcp}"

  read -rp "Hub cluster ingress domain (required): " HUB_DOMAIN
  if [ -z "$HUB_DOMAIN" ]; then
    fail "Hub domain is required."
    exit 1
  fi

  HUB02_DOMAIN=""
  if [ "$MODE" = "multi-hub" ]; then
    read -rp "Second hub ingress domain: " HUB02_DOMAIN
  fi

  read -rp "Number of edge SNO clusters (3): " SPOKE_COUNT
  SPOKE_COUNT="${SPOKE_COUNT:-3}"

  read -rsp "Keycloak broker client secret (required): " KC_SECRET
  echo ""
  if [ -z "$KC_SECRET" ]; then
    fail "Keycloak client secret is required."
    exit 1
  fi

  read -rp "AgnosticD GUID (your GCP sandbox ID, e.g. 725j2): " AGD_GUID
  if [ -z "$AGD_GUID" ]; then
    fail "GUID is required -- find it in your GCP Open Environment email or project name (openenv-XXXXX)"
    exit 1
  fi

  read -rp "AgnosticD account name (openenv-gcp): " AGD_ACCOUNT
  AGD_ACCOUNT="${AGD_ACCOUNT:-openenv-gcp}"

  cat > "$CONFIG_FILE" <<EOF
mode: ${MODE}
cloud_provider: ${CLOUD}
hub_domain: ${HUB_DOMAIN}
hub02_domain: ${HUB02_DOMAIN}
spoke_count: ${SPOKE_COUNT}
keycloak_client_secret: ${KC_SECRET}
agd_guid: ${AGD_GUID}
agd_account: ${AGD_ACCOUNT}
EOF

  pass "Configuration saved to config.yml"
  echo ""
fi

# --- Read config ---
MODE=$(python3 -c "import yaml; print(yaml.safe_load(open('$CONFIG_FILE'))['mode'])")
CLOUD=$(python3 -c "import yaml; print(yaml.safe_load(open('$CONFIG_FILE'))['cloud_provider'])")
HUB_DOMAIN=$(python3 -c "import yaml; print(yaml.safe_load(open('$CONFIG_FILE'))['hub_domain'])")
AGD_GUID=$(python3 -c "import yaml; print(yaml.safe_load(open('$CONFIG_FILE'))['agd_guid'])")
AGD_ACCOUNT=$(python3 -c "import yaml; print(yaml.safe_load(open('$CONFIG_FILE')).get('agd_account','openenv-gcp'))")

echo "Configuration:"
echo "  Mode:           $MODE"
echo "  Cloud:          $CLOUD"
echo "  Hub Domain:     $HUB_DOMAIN"
echo "  GUID:           $AGD_GUID"
echo "  Account:        $AGD_ACCOUNT"
echo ""

# ===================================================================
# Phase 3: Cloud CLI authentication
# ===================================================================
echo "Checking cloud CLI..."
if [ "$CLOUD" = "gcp" ]; then
  if gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | grep -q .; then
    pass "gcloud authenticated as $(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1)"
  else
    warn "gcloud not authenticated"
    echo "  Authenticate with: gcloud auth activate-service-account --key-file=<key.json>"
  fi
elif [ "$CLOUD" = "azure" ]; then
  check_prereq "az" "az account show --query name -o tsv"
fi
echo ""

# ===================================================================
# Phase 4: AgnosticD v2 repo
# ===================================================================
echo "Setting up AgnosticD v2..."
if [ -d "${AGD_DIR}/ansible" ]; then
  pass "AgnosticD v2 repo already cloned at ${AGD_DIR}"
else
  info "Cloning AgnosticD v2 repo..."
  git clone https://github.com/redhat-cop/agnosticd.git "${AGD_DIR}"
  pass "AgnosticD v2 cloned to ${AGD_DIR}"
fi
echo ""

# ===================================================================
# Phase 5: Ansible collections
# ===================================================================
echo "Checking Ansible collections..."
COLLECTIONS_NEEDED=false

if ! ansible-galaxy collection list 2>/dev/null | grep -q "google.cloud"; then
  COLLECTIONS_NEEDED=true
fi
if ! ansible-galaxy collection list 2>/dev/null | grep -q "cloud_provider_gcp"; then
  COLLECTIONS_NEEDED=true
fi

if [ "$COLLECTIONS_NEEDED" = "true" ]; then
  info "Installing Ansible collections..."
  ansible-galaxy collection install \
    google.cloud \
    git+https://github.com/rhpds/core_workloads.git \
    git+https://github.com/tosin2013/cloud_provider_gcp.git
  pass "Ansible collections installed"
else
  pass "Ansible collections already installed"
fi
echo ""

# ===================================================================
# Phase 6: GCP secrets scaffolding
# ===================================================================
if [ "$CLOUD" = "gcp" ]; then
  SECRETS_FILE="${SECRETS_DIR}/secrets-${AGD_ACCOUNT}.yml"

  echo "Checking GCP secrets..."
  mkdir -p "${SECRETS_DIR}"

  if [ -f "${SECRETS_FILE}" ]; then
    pass "Secrets file exists at ${SECRETS_FILE}"
  else
    echo ""
    echo "  No secrets file found. Let's create one."
    echo ""

    read -rp "  GCP sandbox/GUID ID (e.g. 725j2): " SANDBOX_ID
    if [ -z "$SANDBOX_ID" ]; then
      fail "Sandbox ID is required."
      exit 1
    fi

    read -rp "  GCP service account key JSON file path: " GCP_KEY_PATH
    GCP_KEY_PATH="${GCP_KEY_PATH/#\~/$HOME}"
    if [ ! -f "$GCP_KEY_PATH" ]; then
      fail "Key file not found: ${GCP_KEY_PATH}"
      exit 1
    fi

    # Copy key file to secrets dir with standard name if not already there
    GCP_KEY_DEST="${SECRETS_DIR}/gcp-key-${SANDBOX_ID}.json"
    if [ "$GCP_KEY_PATH" != "$GCP_KEY_DEST" ]; then
      cp "$GCP_KEY_PATH" "$GCP_KEY_DEST"
      chmod 600 "$GCP_KEY_DEST"
      info "Key file copied to ${GCP_KEY_DEST}"
    fi

    # Read service account email from key JSON
    GCP_SA_EMAIL=$(python3 -c "import json; print(json.load(open('${GCP_KEY_DEST}'))['client_email'])")
    GCP_SA_PROJECT=$(python3 -c "import json; print(json.load(open('${GCP_KEY_DEST}'))['project_id'])")

    # Authenticate gcloud with the service account for discovery
    if ! gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | grep -q .; then
      info "Authenticating gcloud with service account..."
      gcloud auth activate-service-account --key-file="${GCP_KEY_DEST}" --project="openenv-${SANDBOX_ID}" 2>/dev/null
    fi

    # Discover Open Environment platform variables from GCP
    GCP_PROJECT_ID="openenv-${SANDBOX_ID}"
    info "Discovering platform variables from GCP project ${GCP_PROJECT_ID}..."

    GCP_FOLDER_ID=$(gcloud projects describe "${GCP_PROJECT_ID}" --format='value(parent.id)' 2>/dev/null || echo "")
    GCP_COST_CENTER=$(gcloud projects describe "${GCP_PROJECT_ID}" --format='value(labels.cost-center)' 2>/dev/null || echo "")
    GCP_BILLING_ID=$(gcloud billing projects describe "${GCP_PROJECT_ID}" --format='value(billingAccountName)' 2>/dev/null | sed 's|billingAccounts/||' || echo "")
    GCP_ORG_ID=$(gcloud projects get-ancestors "${GCP_PROJECT_ID}" --format='csv[no-heading](id,type)' 2>/dev/null | awk -F, '$2=="organization"{print $1}' || echo "")
    GCP_BASE_DOMAIN="${SANDBOX_ID}.gcp.redhatworkshops.io"
    GCP_ROOT_DNS_ZONE="gcp.redhatworkshops.io"

    if [ -n "$GCP_FOLDER_ID" ]; then
      pass "Discovered folder ID: ${GCP_FOLDER_ID}"
    else
      warn "Could not discover folder ID -- you may need to add it manually"
    fi
    if [ -n "$GCP_ORG_ID" ]; then
      pass "Discovered organization ID: ${GCP_ORG_ID}"
    else
      warn "Could not discover organization ID -- you may need to add it manually"
    fi

    read -rp "  OpenShift pull secret (paste JSON, or path to file): " PULL_SECRET_INPUT
    if [ -f "$PULL_SECRET_INPUT" ]; then
      OCP_PULL_SECRET=$(cat "$PULL_SECRET_INPUT")
    else
      OCP_PULL_SECRET="$PULL_SECRET_INPUT"
    fi

    # Write the secrets file
    cat > "${SECRETS_FILE}" <<EOF
---
# Generated by bootstrap.sh for sandbox ${SANDBOX_ID}
# DO NOT commit this file to Git.

base_domain: "${GCP_BASE_DOMAIN}"
gcp_project_id: "${GCP_PROJECT_ID}"
gcp_region: "us-east1"
gcp_service_account: "${GCP_SA_EMAIL}"
gcp_credentials_file: "${GCP_KEY_DEST}"

# RHDP Open Environment platform variables
agnosticd_open_environment: true
requester_email: "$(git config user.email || echo 'changeme@redhat.com')"
gcp_open_env_folder_id: "${GCP_FOLDER_ID}"
gcp_cost_center: "${GCP_COST_CENTER}"
gcp_billing_account_id: "${GCP_BILLING_ID}"
gcp_admin_group: "group:rhdp-gcp-admins@redhat.com"
project_name: "${GCP_PROJECT_ID}"
gcp_organization: "${GCP_ORG_ID}"
gcp_root_dns_zone: "${GCP_ROOT_DNS_ZONE}"
service_account_email: "${GCP_SA_EMAIL}"

# OpenShift pull secret
ocp4_pull_secret: >-
  ${OCP_PULL_SECRET}

# Note: GCP RHEL cloud images have repos pre-configured via RHUI.
# Satellite settings are not needed for GCP deployments.
EOF

    chmod 600 "${SECRETS_FILE}"
    pass "Secrets file written to ${SECRETS_FILE}"
  fi

  # Verify GCP key file exists
  GCP_KEY_FILE=$(find "${SECRETS_DIR}" -name "gcp-key-*.json" 2>/dev/null | head -1)
  if [ -n "${GCP_KEY_FILE}" ]; then
    pass "GCP service account key found: ${GCP_KEY_FILE}"
  else
    fail "No GCP key file (gcp-key-*.json) found in ${SECRETS_DIR}/"
  fi
  echo ""
fi

# ===================================================================
# Phase 7: TLS Generation
# ===================================================================
echo "Generating TLS certificates..."
if [ ! -f "${SCRIPT_DIR}/artemis/tls/hub-01-broker-keystore.jks" ]; then
  export KC_DOMAIN="$HUB_DOMAIN"
  export HUB01_DOMAIN="$HUB_DOMAIN"
  HUB02_DOMAIN=$(python3 -c "import yaml; d=yaml.safe_load(open('$CONFIG_FILE')); print(d.get('hub02_domain','') or d['hub_domain'])")
  export HUB02_DOMAIN
  "${SCRIPT_DIR}/scripts/generate-tls.sh"
  pass "TLS certificates generated"
else
  pass "TLS certificates already exist"
fi
echo ""

# ===================================================================
# Phase 8: Pre-deploy validation
# ===================================================================
echo "Running pre-deploy validation..."

PREFAIL=0
pre_check() {
  local name="$1" cmd="$2"
  if eval "$cmd" >/dev/null 2>&1; then
    pass "$name"
  else
    fail "$name"
    PREFAIL=$((PREFAIL + 1))
  fi
}

pre_check "Helm template renders"    "helm template '${SCRIPT_DIR}' --values '${SCRIPT_DIR}/values.yaml'"
pre_check "TLS keystores exist"      "test -f '${SCRIPT_DIR}/artemis/tls/hub-01-broker-keystore.jks'"
pre_check "AgnosticD v2 repo"        "test -d '${AGD_DIR}/ansible'"

if [ "$CLOUD" = "gcp" ]; then
  pre_check "Cloud CLI authenticated"    "gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -1 | grep -q ."
  pre_check "GCP secrets file"           "test -f '${SECRETS_DIR}/secrets-${AGD_ACCOUNT}.yml'"
  pre_check "GCP service account key"    "find '${SECRETS_DIR}' -name 'gcp-key-*.json' | head -1 | grep -q ."
fi

if [ "$PREFAIL" -gt 0 ]; then
  fail "$PREFAIL pre-deploy checks failed. Fix them before deploying."
  echo ""
else
  pass "All pre-deploy checks passed"
  echo ""
fi

# ===================================================================
# Phase 9: Post-deploy validation (only if OpenShift is reachable)
# ===================================================================
echo "Running post-deploy validation..."
if oc whoami >/dev/null 2>&1; then
  pass "Logged into OpenShift as $(oc whoami)"

  if oc get mch -A --no-headers 2>/dev/null | grep -q .; then
    pass "RHACM MultiClusterHub found"
  else
    warn "RHACM not detected (will be installed during deployment)"
  fi

  if oc get sub -n openshift-operators amq-broker-rhel8 --no-headers 2>/dev/null | grep -q .; then
    pass "AMQ Broker operator installed"
  else
    warn "AMQ Broker operator not installed (will be deployed by chart)"
  fi
else
  info "Not logged into OpenShift -- post-deploy checks skipped (expected before first deployment)"
fi
echo ""

# ===================================================================
# Summary
# ===================================================================
echo "============================================"
echo "  Bootstrap complete!"
echo "============================================"
echo ""
echo "Next steps:"
if [ "$PREFAIL" -gt 0 ]; then
  echo "  1. Fix the $PREFAIL failing pre-deploy check(s) above"
  echo "  2. Re-run: ./bootstrap.sh"
else
  echo "  1. Deploy OpenShift on GCP:"
  echo "     ./scripts/deploy.sh --guid ${AGD_GUID} --account ${AGD_ACCOUNT}"
  echo ""
  echo "  2. After provisioning completes, save deployment info:"
  echo "     ./scripts/save-deployment-info.sh ${AGD_GUID}"
  echo ""
  echo "  3. Re-run bootstrap to validate the deployed cluster:"
  echo "     ./bootstrap.sh"
fi
