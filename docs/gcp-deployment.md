# GCP Deployment Guide

Deploy the Artemis Edge ACM Demo on Google Cloud Platform using AgnosticD v2.

## Prerequisites

| Tool | Purpose | Install |
|------|---------|---------|
| `gcloud` | GCP CLI | [Install Guide](https://cloud.google.com/sdk/docs/install) |
| `ansible-navigator` | Run Ansible with execution environments | `pip3 install --user 'ansible-navigator[ansible-core]'` |
| `oc` | OpenShift CLI | [Download](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/) |
| `helm` | Helm chart validation | `curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \| bash` |
| `java` (21+) | Java client builds | `sudo dnf install -y java-21-openjdk-devel` |
| `mvn` | Maven builds | `sudo dnf install -y maven` |

## Quick Start

```bash
# 1. Clone and enter the repo
git clone https://github.com/tosin2013/artemis-edge-acm-demo.git
cd artemis-edge-acm-demo

# 2. Run bootstrap (interactive — installs deps, scaffolds secrets)
./bootstrap.sh

# 3. Deploy OpenShift + workloads
./scripts/deploy.sh --guid artgcp --account openenv-gcp

# 4. Tear down when done
./scripts/deploy.sh --destroy --guid artgcp --account openenv-gcp
```

## What bootstrap.sh Does

1. **Checks prerequisites** — validates all required CLI tools are installed
2. **Prompts for configuration** — deployment mode, cloud provider, domains, credentials
3. **Authenticates gcloud** — using your service account key
4. **Clones AgnosticD v2** — to `~/Development/agnosticd-v2`
5. **Installs Ansible collections** — `google.cloud`, `core_workloads`, `cloud_provider_gcp`
6. **Scaffolds GCP secrets** — auto-discovers platform variables from `gcloud`, prompts for the rest
7. **Generates TLS certificates** — for broker and Keycloak mTLS
8. **Validates** — runs pre-deploy checks before you deploy

## GCP Secrets File

`bootstrap.sh` creates `~/Development/agnosticd-v2-secrets/secrets-openenv-gcp.yml` with these required variables:

| Variable | Source | Description |
|----------|--------|-------------|
| `base_domain` | Derived from sandbox ID | e.g. `725j2.gcp.redhatworkshops.io` |
| `gcp_project_id` | Derived from sandbox ID | e.g. `openenv-725j2` |
| `gcp_service_account` | Read from key JSON | Service account email |
| `gcp_credentials_file` | User-provided path | Path to service account JSON key |
| `gcp_open_env_folder_id` | `gcloud projects describe` | GCP folder ID |
| `gcp_cost_center` | `gcloud projects describe` | Cost center label |
| `gcp_billing_account_id` | `gcloud billing projects describe` | Billing account ID |
| `gcp_organization` | `gcloud projects get-ancestors` | Organization ID |
| `gcp_root_dns_zone` | Static | `gcp.redhatworkshops.io` |
| `service_account_email` | Read from key JSON | Same as `gcp_service_account` |
| `ocp4_pull_secret` | User-provided | From [console.redhat.com](https://console.redhat.com/openshift/install/pull-secret) |

## Key vars.yml Settings

The following settings in `agnosticd/gcp/vars.yml` are critical for GCP Open Environment deployments:

```yaml
# Without this, OpenShift is not installed (Software Playbook = NONE)
software_to_deploy: openshift4

# Must match existing DNS zone — default adds guid prefix which breaks lookup
ocp4_base_domain: "{{ base_domain }}"

# GCP RHEL images use RHUI, not Satellite
repo_method: none

# Skip project creation for existing RHDP Open Environments
gcp_create_open_env_project: false

# Load GCP credentials from key file at runtime
gcp_credentials: "{{ lookup('file', gcp_credentials_file) | from_json }}"
```

## Upstream AgnosticD Patch

When deploying to an **existing** RHDP Open Environment (where `gcp_create_open_env_project: false`), a local patch is required to AgnosticD's `pre_infra.yml`:

**File:** `~/Development/agnosticd-v2/ansible/configs/ocp4-cluster/pre_infra.yml`

### What the patch does

1. **Keeps** `infra-gcp-credentials-file` role running unconditionally (credentials are always needed)
2. **Adds** a task to create `svc-acct-creds.json` when project creation is skipped

Without this patch, the `host-ocp4-provisioner` role fails because `svc-acct-creds.json` is normally created as a side effect of `open-env-gcp-add-user-to-project`, which is skipped when not creating a new project.

### The patch

```yaml
    - name: Create GCP Credentials File
      ansible.builtin.include_role:
        name: infra-gcp-credentials-file

    - name: Create svc-acct-creds.json for host-ocp4-provisioner
      when: not (gcp_create_open_env_project | default(true) | bool)
      ansible.builtin.copy:
        dest: "{{ output_dir }}/svc-acct-creds.json"
        mode: "0644"
        content: "{{ gcp_credentials | to_json if gcp_credentials is mapping else gcp_credentials }}"
```

> **TODO:** Upstream this as a PR to [rhpds/agnosticd](https://github.com/redhat-cop/agnosticd) so the patch is not needed.

## deploy.sh Usage

```
Usage: ./scripts/deploy.sh [OPTIONS]

Options:
  --guid GUID        Deployment GUID (default: artgcp)
  --account ACCOUNT  Secrets account name (default: openenv-gcp)
  --tags TAGS        Ansible tags to run (e.g. step003,step005)
  --action ACTION    AgnosticD action: provision, destroy, stop, status
  --destroy          Shorthand for --action destroy
  --stop             Shorthand for --action stop
  --status           Shorthand for --action status
  -h, --help         Show this help message
```

## Troubleshooting

### Error: 409 Conflict during `gcloud deployment-manager create`

The GCP Deployment Manager resource already exists from a prior run. The `gcp_infrastructure_deployment.yml` patch makes this idempotent — if the deployment exists, it skips creation.

### Error: `no matching public DNS Zone found`

`ocp4_base_domain` is wrong. Ensure `vars.yml` has:
```yaml
ocp4_base_domain: "{{ base_domain }}"
```

### Error: `software_to_deploy` not set / Software Playbook NONE

Add to `vars.yml`:
```yaml
software_to_deploy: openshift4
```

### Error: `svc-acct-creds.json` not found

Apply the `pre_infra.yml` patch described above.

### Error: Satellite URL error (`no host given`)

Set in `vars.yml`:
```yaml
repo_method: none
```

## Related Issues

- [#22](https://github.com/tosin2013/artemis-edge-acm-demo/issues/22) — Fix onboarding gaps
- [#23](https://github.com/tosin2013/artemis-edge-acm-demo/issues/23) — bootstrap.sh automation
- [#24](https://github.com/tosin2013/artemis-edge-acm-demo/issues/24) — deploy.sh --destroy flag
