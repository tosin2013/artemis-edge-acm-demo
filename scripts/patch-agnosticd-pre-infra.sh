#!/usr/bin/env bash
set -euo pipefail
#
# scripts/patch-agnosticd-pre-infra.sh — Patch AgnosticD pre_infra.yml
#
# Adds a task to create svc-acct-creds.json when gcp_create_open_env_project
# is false. Without this, host-ocp4-provisioner fails because the file is
# normally created by open-env-gcp-add-user-to-project (skipped when not
# creating a new project).
#
# Usage:
#   ./scripts/patch-agnosticd-pre-infra.sh <agnosticd-root>
#
# Idempotent: safe to run multiple times.

AGD_ROOT="${1:?Usage: patch-agnosticd-pre-infra.sh <agnosticd-root>}"
AGD_ROOT="${AGD_ROOT/#\~/$HOME}"

PRE_INFRA="${AGD_ROOT}/ansible/configs/openshift-cluster/pre_infra.yml"

if [[ ! -f "$PRE_INFRA" ]]; then
  echo "ERROR: pre_infra.yml not found at ${PRE_INFRA}" >&2
  echo "Is AgnosticD cloned at ${AGD_ROOT}?" >&2
  exit 1
fi

# Check if patch is already applied
if grep -q 'svc-acct-creds.json' "$PRE_INFRA" 2>/dev/null; then
  echo "  [OK] AgnosticD pre_infra.yml patch already applied"
  exit 0
fi

echo "  Patching ${PRE_INFRA}..."

# Insert the svc-acct-creds.json task after the "Create GCP Credentials File" block.
# We look for the credentials_file include_role and append after it.
python3 -c "
import sys

with open(sys.argv[1], 'r') as f:
    content = f.read()

# The patch task to insert (must match the YAML indentation of the file)
patch = '''
    - name: Create svc-acct-creds.json for host-ocp4-provisioner
      when: not (gcp_create_open_env_project | default(true) | bool)
      ansible.builtin.copy:
        dest: \"{{ output_dir }}/svc-acct-creds.json\"
        mode: \"0644\"
        content: \"{{ gcp_credentials | to_json if gcp_credentials is mapping else gcp_credentials }}\"
'''

# Find the credentials_file role inclusion and insert after it
marker = 'name: agnosticd.cloud_provider_gcp.credentials_file'
if marker not in content:
    print('ERROR: Could not find credentials_file role in pre_infra.yml', file=sys.stderr)
    sys.exit(1)

# Find the end of that task block (next line that starts a new task or block)
lines = content.split('\n')
insert_after = None
for i, line in enumerate(lines):
    if marker in line:
        insert_after = i
        break

if insert_after is None:
    print('ERROR: marker line not found', file=sys.stderr)
    sys.exit(1)

# Insert after the credentials_file role line
lines.insert(insert_after + 1, patch.rstrip())

with open(sys.argv[1], 'w') as f:
    f.write('\n'.join(lines))

print('  [OK] Patch applied successfully')
" "$PRE_INFRA"
