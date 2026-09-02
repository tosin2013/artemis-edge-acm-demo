#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.yml"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo "============================================"
echo "  Artemis Edge ACM Demo -- Bootstrap"
echo "============================================"
echo ""

# --- Prerequisites ---
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

if [ "$MISSING" -gt 0 ]; then
  fail "$MISSING prerequisites missing. Install them and re-run."
  exit 1
fi
echo ""

# --- Configuration ---
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

  cat > "$CONFIG_FILE" <<EOF
mode: ${MODE}
cloud_provider: ${CLOUD}
hub_domain: ${HUB_DOMAIN}
hub02_domain: ${HUB02_DOMAIN}
spoke_count: ${SPOKE_COUNT}
keycloak_client_secret: ${KC_SECRET}
EOF

  pass "Configuration saved to config.yml"
  echo ""
fi

# --- Read config ---
MODE=$(python3 -c "import yaml; print(yaml.safe_load(open('$CONFIG_FILE'))['mode'])")
CLOUD=$(python3 -c "import yaml; print(yaml.safe_load(open('$CONFIG_FILE'))['cloud_provider'])")
HUB_DOMAIN=$(python3 -c "import yaml; print(yaml.safe_load(open('$CONFIG_FILE'))['hub_domain'])")

echo "Configuration:"
echo "  Mode:           $MODE"
echo "  Cloud:          $CLOUD"
echo "  Hub Domain:     $HUB_DOMAIN"
echo ""

# --- Cloud CLI check ---
echo "Checking cloud CLI..."
if [ "$CLOUD" = "gcp" ]; then
  check_prereq "gcloud" "gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -1"
elif [ "$CLOUD" = "azure" ]; then
  check_prereq "az" "az account show --query name -o tsv"
fi
echo ""

# --- TLS Generation ---
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

# --- Validation ---
echo "Running validation..."
if oc whoami >/dev/null 2>&1; then
  pass "Logged into OpenShift as $(oc whoami)"
else
  warn "Not logged into OpenShift -- deploy will fail"
fi

if oc get mch -A --no-headers 2>/dev/null | grep -q .; then
  pass "RHACM MultiClusterHub found"
else
  warn "RHACM not detected"
fi

if helm template "${SCRIPT_DIR}" --values "${SCRIPT_DIR}/values.yaml" >/dev/null 2>&1; then
  pass "Helm template renders cleanly"
else
  fail "Helm template failed -- check values.yaml"
fi

echo ""
echo "============================================"
echo "  Bootstrap complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Log in to your OpenShift hub cluster"
echo "  2. Deploy with: helm install artemis-edge . -f values.yaml"
echo "  3. For Mode 2: helm install artemis-edge . -f values.yaml -f values-mode2.yaml"
