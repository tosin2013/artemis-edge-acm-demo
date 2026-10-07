#!/usr/bin/env bash
set -euo pipefail
#
# Extract key deployment info from agnosticd-v2-output and write
# deployment-info.yml in the project root (git-ignored).
#
# Designed to be re-run after every cluster rebuild — always reads fresh
# data from provision-user-data.yaml and picks the newest kubeconfig.
#
# Usage:
#   Auto-detect (recommended — infers mode from output directories):
#     ./scripts/save-deployment-info.sh
#
#   Single-hub (explicit):
#     ./scripts/save-deployment-info.sh [GUID]
#
#   Multi-hub (explicit):
#     ./scripts/save-deployment-info.sh --mode multi-hub --sandbox <SANDBOX_ID>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
AGD_BASE="${AGD_OUTPUT_DIR:-${HOME}/Development/agnosticd-v2-output}"
DEST="${PROJECT_ROOT}/deployment-info.yml"

MODE=""
SANDBOX=""

# ── Argument parsing ──────────────────────────────────────────────────
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"; shift 2 ;;
    --sandbox)
      SANDBOX="$2"; shift 2 ;;
    *)
      args+=("$1"); shift ;;
  esac
done

if ! command -v python3 &>/dev/null; then
  echo "ERROR: python3 is required" >&2
  exit 1
fi

# ── Auto-detect mode when no --mode flag is given ─────────────────────
if [[ -z "${MODE}" && ${#args[@]} -eq 0 ]]; then
  # Try config.yml first for the GUID / sandbox hint
  CONFIG_FILE="${PROJECT_ROOT}/config.yml"
  CONFIG_GUID=""
  CONFIG_MODE=""
  if [[ -f "${CONFIG_FILE}" ]]; then
    CONFIG_GUID=$(python3 -c "import yaml; print(yaml.safe_load(open('${CONFIG_FILE}')).get('agd_guid',''))" 2>/dev/null) || true
    CONFIG_MODE=$(python3 -c "import yaml; print(yaml.safe_load(open('${CONFIG_FILE}')).get('mode',''))" 2>/dev/null) || true
  fi

  # Scan output directories for multi-hub pattern: multiple dirs sharing
  # the same sandbox suffix (e.g. east-ctbz4, west-ctbz4, global-ctbz4)
  _detected_sandbox=""
  _detected_count=0
  if [[ -d "${AGD_BASE}" ]]; then
    # Build a map of suffix → count from directory names containing a hyphen
    declare -A _suffix_counts=()
    for d in "${AGD_BASE}"/*/; do
      [[ -d "$d" ]] || continue
      dname="$(basename "$d")"
      # Only consider dirs with a hyphen (e.g. east-ctbz4, not standalone GUIDs)
      if [[ "$dname" == *-* ]]; then
        suffix="${dname##*-}"
        _suffix_counts["$suffix"]=$(( ${_suffix_counts["$suffix"]:-0} + 1 ))
      fi
    done

    # Find the suffix with the most matches (≥2 means multi-hub)
    for suffix in "${!_suffix_counts[@]}"; do
      if (( _suffix_counts["$suffix"] >= 2 && _suffix_counts["$suffix"] > _detected_count )); then
        _detected_sandbox="$suffix"
        _detected_count="${_suffix_counts["$suffix"]}"
      fi
    done
  fi

  if (( _detected_count >= 2 )); then
    MODE="multi-hub"
    # Prefer config.yml agd_guid when it matches a valid multi-hub suffix
    # (disambiguates ties when multiple sandboxes exist in the output dir)
    if [[ -n "${CONFIG_GUID}" ]] && (( ${_suffix_counts["${CONFIG_GUID}"]:-0} >= 2 )); then
      SANDBOX="${CONFIG_GUID}"
    else
      SANDBOX="${_detected_sandbox}"
    fi
    unset _suffix_counts
    echo "Auto-detected multi-hub mode (sandbox: ${SANDBOX}, ${_detected_count} hubs found)" >&2
  elif [[ -n "${CONFIG_GUID}" ]]; then
    # Single-hub: use the GUID from config.yml
    OUTPUT_CHECK="${AGD_BASE}/${CONFIG_GUID}"
    if [[ -d "${OUTPUT_CHECK}" ]]; then
      args+=("${CONFIG_GUID}")
    else
      echo "WARNING: config.yml references GUID '${CONFIG_GUID}' but no matching output directory exists at ${OUTPUT_CHECK}." >&2
      echo "  Run bootstrap.sh to reconfigure, or pass the GUID explicitly." >&2
      exit 1
    fi
  else
    echo "ERROR: Cannot auto-detect deployment. Pass a GUID, or use --mode multi-hub --sandbox <id>." >&2
    exit 1
  fi
fi

# ── Multi-hub mode ────────────────────────────────────────────────────
if [[ "${MODE}" == "multi-hub" ]]; then
  if [[ -z "${SANDBOX}" ]]; then
    echo "ERROR: --sandbox <SANDBOX_ID> is required with --mode multi-hub" >&2
    exit 1
  fi

  # Discover all hub directories matching *-<SANDBOX>
  HUB_DIRS=()
  for d in "${AGD_BASE}"/*-"${SANDBOX}"; do
    [[ -d "$d" ]] && HUB_DIRS+=("$d")
  done

  if [[ ${#HUB_DIRS[@]} -eq 0 ]]; then
    echo "ERROR: No hub directories matching *-${SANDBOX} found in ${AGD_BASE}" >&2
    exit 1
  fi

  # Build a space-separated list of dir paths for the Python script
  python3 - "${DEST}" "${SANDBOX}" "${HUB_DIRS[@]}" <<'PYEOF'
import sys, yaml, os, glob

dest_path  = sys.argv[1]
sandbox_id = sys.argv[2]
hub_dirs   = sys.argv[3:]

# Role mapping: directory-name prefix → human role label
ROLE_MAP = {
    "global": "global",
    "east":   "east",
    "cen":    "central",
    "west":   "west",
}

def query_showroom_route(kubeconfig_path):
    """Live cluster fallback: query Showroom route via oc. Returns URL or ''."""
    import subprocess
    try:
        result = subprocess.run(
            ["oc", "get", "route", "showroom", "-n", "showroom",
             "-o", "jsonpath={.spec.host}"],
            env={**os.environ, "KUBECONFIG": kubeconfig_path},
            capture_output=True, text=True, timeout=10,
        )
        host = result.stdout.strip()
        if host:
            return f"https://{host}"
    except Exception:
        pass
    return ""

def extract_hub_info(user_data_path, output_dir):
    """Extract the same fields as single-hub mode for one hub."""
    with open(user_data_path) as f:
        data = yaml.safe_load(f)

    guid = data.get("guid", "")
    info = {
        "guid": guid,
        "cloud_provider": data.get("cloud_provider", ""),
        "openshift_api_url": data.get("openshift_api_url", ""),
        "openshift_console_url": data.get("openshift_console_url",
                                 data.get("openshift_cluster_console_url", "")),
        "openshift_cluster_ingress_domain": data.get("openshift_cluster_ingress_domain", ""),
        "openshift_cluster_admin_username": data.get("openshift_cluster_admin_username", "kubeadmin"),
        "openshift_cluster_admin_password": data.get("openshift_cluster_admin_password",
                                           data.get("openshift_kubeadmin_password", "")),
        "bastion_public_hostname": data.get("bastion_public_hostname", ""),
        "bastion_ssh_user_name": data.get("bastion_ssh_user_name", ""),
        "bastion_ssh_password": data.get("bastion_ssh_password", ""),
        "openshift_gitops_server": data.get("openshift_gitops_server", ""),
    }

    # RHACM console URL
    rhacm_url = data.get("rhacm_console_url", "")
    if not rhacm_url:
        domain = data.get("openshift_cluster_ingress_domain", "")
        if domain:
            rhacm_url = f"https://multicloud-console.apps.{domain.removeprefix('apps.')}"
    info["rhacm_console_url"] = rhacm_url
    info["rhacm_namespace"] = "open-cluster-management"

    # Showroom URL — from provision data first
    showroom_url = data.get("showroom_url", "")
    users = data.get("users", {})
    if not showroom_url and users:
        first_user = next(iter(users.values()), {})
        showroom_url = first_user.get("showroom_primary_view_url",
                       first_user.get("lab_ui_url", ""))

    # Kubeconfig (resolve early — needed for live fallback)
    kubeconfig_path = ""
    kubeconfig_matches = glob.glob(os.path.join(output_dir, f"*_{guid}_kubeconfig"))
    if kubeconfig_matches:
        kubeconfig_path = max(kubeconfig_matches, key=os.path.getmtime)

    # Live cluster fallback: query Showroom route if provision data is empty
    if not showroom_url and kubeconfig_path:
        showroom_url = query_showroom_route(kubeconfig_path)
        if showroom_url:
            print(f"  Live cluster fallback: detected Showroom at {showroom_url}", file=sys.stderr)
    info["showroom_url"] = showroom_url

    # GCP info
    if data.get("gcp_project_id"):
        info["gcp_project_id"] = data["gcp_project_id"]
        info["gcp_region"] = data.get("gcp_region", "")
        info["gcp_console_url"] = data.get("gcp_console_url", "")

    # Users section
    if users:
        info["users"] = {}
        for name, u in users.items():
            user_info = {
                "password": u.get("password", ""),
                "login_command": u.get("login_command", ""),
            }
            u_showroom = u.get("showroom_primary_view_url", "")
            if u_showroom:
                user_info["showroom_url"] = u_showroom
            if u.get("lab_ui_url"):
                user_info["lab_ui_url"] = u["lab_ui_url"]
            # Live cluster fallback: if no per-user showroom URL but route exists,
            # use the base showroom URL for all users
            if not u_showroom and not u.get("lab_ui_url") and showroom_url:
                user_info["showroom_url"] = showroom_url
                user_info["lab_ui_url"] = showroom_url
            info["users"][name] = user_info

    if kubeconfig_path:
        info["kubeconfig_path"] = kubeconfig_path

    return info

def role_from_dirname(dirname, sandbox_id):
    """Derive the role label from a directory name like 'global-ctbz4'."""
    prefix = dirname.removesuffix(f"-{sandbox_id}")
    return ROLE_MAP.get(prefix, prefix)

hubs = {}
for hub_dir in sorted(hub_dirs):
    dirname = os.path.basename(hub_dir)
    user_data = os.path.join(hub_dir, "provision-user-data.yaml")
    if not os.path.isfile(user_data):
        print(f"WARNING: {user_data} not found, skipping {dirname}", file=sys.stderr)
        continue
    role = role_from_dirname(dirname, sandbox_id)
    hubs[role] = extract_hub_info(user_data, hub_dir)

# Reorder: global (hub-of-hubs) first, then regional hubs alphabetically
ROLE_ORDER = ["global", "east", "central", "west"]
ordered_hubs = {k: hubs[k] for k in ROLE_ORDER if k in hubs}
ordered_hubs.update({k: v for k, v in hubs.items() if k not in ordered_hubs})

output = {
    "mode": "multi-hub",
    "sandbox": sandbox_id,
    "hubs": ordered_hubs,
}

with open(dest_path, "w") as f:
    f.write("# Generated by scripts/save-deployment-info.sh — DO NOT COMMIT\n")
    f.write("# Re-run the script to refresh after a new deployment\n")
    yaml.dump(output, f, default_flow_style=False, sort_keys=False)

# Generate human-friendly markdown summary
md_path = dest_path.replace(".yml", ".md")
with open(md_path, "w") as md:
    md.write(f"# Deployment Info — Sandbox `{sandbox_id}` (Multi-Hub)\n\n")
    md.write(f"> Auto-generated by `scripts/save-deployment-info.sh` — do not edit manually.\n")
    md.write(f"> Re-run the script to refresh after a new deployment.\n\n")
    md.write(f"**Mode:** multi-hub &nbsp;|&nbsp; **Sandbox:** `{sandbox_id}` &nbsp;|&nbsp; **Hubs:** {len(ordered_hubs)}\n\n")
    md.write("---\n\n")
    for i, (role, h) in enumerate(ordered_hubs.items(), 1):
        badge = "🌐 Global Hub-of-Hubs" if role == "global" else f"🏢 Regional Hub"
        md.write(f"## {i}. {role.capitalize()} — {badge}\n\n")
        md.write(f"| Property | Value |\n|---|---|\n")
        md.write(f"| **GUID** | `{h.get('guid', 'N/A')}` |\n")
        md.write(f"| **API URL** | `{h.get('openshift_api_url', 'N/A')}` |\n")
        md.write(f"| **Console** | [{h.get('openshift_console_url', '')}]({h.get('openshift_console_url', '')}) |\n")
        md.write(f"| **Ingress Domain** | `{h.get('openshift_cluster_ingress_domain', 'N/A')}` |\n")
        md.write(f"| **Cluster Admin** | `{h.get('openshift_cluster_admin_username', 'admin')}` / `{h.get('openshift_cluster_admin_password', 'N/A')}` |\n")
        md.write(f"| **Bastion** | `{h.get('bastion_ssh_user_name', '')}@{h.get('bastion_public_hostname', '')}` (pw: `{h.get('bastion_ssh_password', 'N/A')}`) |\n")
        md.write(f"| **Argo CD** | [{h.get('openshift_gitops_server', '')}]({h.get('openshift_gitops_server', '')}) |\n")
        md.write(f"| **RHACM Console** | [{h.get('rhacm_console_url', '')}]({h.get('rhacm_console_url', '')}) |\n")
        sr = h.get("showroom_url", "")
        if sr:
            md.write(f"| **Showroom** | [{sr}]({sr}) |\n")
        md.write(f"| **GCP Project** | `{h.get('gcp_project_id', 'N/A')}` / `{h.get('gcp_region', 'N/A')}` |\n")
        md.write(f"| **Kubeconfig** | `{h.get('kubeconfig_path', 'N/A')}` |\n")
        md.write("\n")
        users = h.get("users", {})
        if users:
            md.write("### Users\n\n")
            md.write("| User | Password | Login Command |\n|---|---|---|\n")
            for uname, udata in users.items():
                pw = udata.get("password", "N/A")
                cmd = udata.get("login_command", "N/A")
                md.write(f"| `{uname}` | `{pw}` | `{cmd}` |\n")
            md.write("\n")
        md.write("---\n\n")

    md.write(f"*Generated at: {os.popen('date -Iseconds').read().strip()}*\n")

print(f"Multi-hub deployment info saved to: {dest_path}")
print(f"  Human-friendly summary: {md_path}")
print(f"  Hubs discovered: {', '.join(ordered_hubs.keys())}")
PYEOF

  exit 0
fi

# ── Single-hub mode (original behaviour) ─────────────────────────────
if [[ ${#args[@]} -gt 0 ]]; then
  GUID="${args[0]}"
elif [[ -n "${AGD_GUID:-}" ]]; then
  GUID="$AGD_GUID"
elif [[ -f "${PROJECT_ROOT}/config.yml" ]]; then
  GUID=$(python3 -c "import yaml; print(yaml.safe_load(open('${PROJECT_ROOT}/config.yml'))['agd_guid'])" 2>/dev/null) || true
fi
if [[ -z "${GUID:-}" ]]; then
  echo "ERROR: GUID required. Pass as argument, set AGD_GUID, or run bootstrap.sh first." >&2
  exit 1
fi
OUTPUT_DIR="${AGD_BASE}/${GUID}"
USER_DATA="${OUTPUT_DIR}/provision-user-data.yaml"

if [[ ! -f "${USER_DATA}" ]]; then
  echo "ERROR: ${USER_DATA} not found." >&2
  echo "Run 'agd provision' first, or set AGD_OUTPUT_DIR." >&2
  exit 1
fi

python3 - "${USER_DATA}" "${OUTPUT_DIR}" "${DEST}" <<'PYEOF'
import sys, yaml, os, glob, subprocess

user_data_path = sys.argv[1]
output_dir     = sys.argv[2]
dest_path      = sys.argv[3]

def query_showroom_route(kubeconfig_path):
    """Live cluster fallback: query Showroom route via oc. Returns URL or ''."""
    try:
        result = subprocess.run(
            ["oc", "get", "route", "showroom", "-n", "showroom",
             "-o", "jsonpath={.spec.host}"],
            env={**os.environ, "KUBECONFIG": kubeconfig_path},
            capture_output=True, text=True, timeout=10,
        )
        host = result.stdout.strip()
        if host:
            return f"https://{host}"
    except Exception:
        pass
    return ""

with open(user_data_path) as f:
    data = yaml.safe_load(f)

guid = data.get("guid", "")

info = {
    "guid": guid,
    "cloud_provider": data.get("cloud_provider", ""),
    "openshift_api_url": data.get("openshift_api_url", ""),
    "openshift_console_url": data.get("openshift_console_url",
                             data.get("openshift_cluster_console_url", "")),
    "openshift_cluster_ingress_domain": data.get("openshift_cluster_ingress_domain", ""),
    "openshift_cluster_admin_username": data.get("openshift_cluster_admin_username", "kubeadmin"),
    "openshift_cluster_admin_password": data.get("openshift_cluster_admin_password",
                                       data.get("openshift_kubeadmin_password", "")),
    "bastion_public_hostname": data.get("bastion_public_hostname", ""),
    "bastion_ssh_user_name": data.get("bastion_ssh_user_name", ""),
    "bastion_ssh_password": data.get("bastion_ssh_password", ""),
    "openshift_gitops_server": data.get("openshift_gitops_server", ""),
}

# RHACM console URL — construct from ingress domain if not in user-data
rhacm_url = data.get("rhacm_console_url", "")
if not rhacm_url:
    domain = data.get("openshift_cluster_ingress_domain", "")
    if domain:
        rhacm_url = f"https://multicloud-console.apps.{domain.removeprefix('apps.')}"
info["rhacm_console_url"] = rhacm_url
info["rhacm_namespace"] = "open-cluster-management"

# Showroom URL — use first user's showroom URL if available
showroom_url = data.get("showroom_url", "")
users = data.get("users", {})
if not showroom_url and users:
    first_user = next(iter(users.values()), {})
    showroom_url = first_user.get("showroom_primary_view_url",
                   first_user.get("lab_ui_url", ""))

# Kubeconfig — prefer the newest file matching *_GUID_kubeconfig
kubeconfig_path = ""
kubeconfig_matches = glob.glob(os.path.join(output_dir, f"*_{guid}_kubeconfig"))
if kubeconfig_matches:
    kubeconfig_path = max(kubeconfig_matches, key=os.path.getmtime)

# Live cluster fallback: query Showroom route if provision data is empty
if not showroom_url and kubeconfig_path:
    showroom_url = query_showroom_route(kubeconfig_path)
    if showroom_url:
        print(f"  Live cluster fallback: detected Showroom at {showroom_url}", file=sys.stderr)
info["showroom_url"] = showroom_url

# GCP info
if data.get("gcp_project_id"):
    info["gcp_project_id"] = data["gcp_project_id"]
    info["gcp_region"] = data.get("gcp_region", "")
    info["gcp_console_url"] = data.get("gcp_console_url", "")

# Users section
if users:
    info["users"] = {}
    for name, u in users.items():
        user_info = {
            "password": u.get("password", ""),
            "login_command": u.get("login_command", ""),
        }
        u_showroom = u.get("showroom_primary_view_url", "")
        if u_showroom:
            user_info["showroom_url"] = u_showroom
        if u.get("lab_ui_url"):
            user_info["lab_ui_url"] = u["lab_ui_url"]
        # Live cluster fallback: use base showroom URL for users without their own
        if not u_showroom and not u.get("lab_ui_url") and showroom_url:
            user_info["showroom_url"] = showroom_url
            user_info["lab_ui_url"] = showroom_url
        info["users"][name] = user_info

if kubeconfig_path:
    info["kubeconfig_path"] = kubeconfig_path

with open(dest_path, "w") as f:
    f.write("# Generated by scripts/save-deployment-info.sh — DO NOT COMMIT\n")
    f.write("# Re-run the script to refresh after a new deployment\n")
    yaml.dump(info, f, default_flow_style=False, sort_keys=False)

print(f"Deployment info saved to: {dest_path}")
PYEOF
