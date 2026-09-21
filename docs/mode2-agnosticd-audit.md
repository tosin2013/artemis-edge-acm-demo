# AgnosticD Refactor Audit — Config: Mode 2 (`openshift-cluster` + multihub vars)

Authority: [#77](https://github.com/tosin2013/artemis-edge-acm-demo/issues/77). Static audit (no live GUID). Do not use `7d2ft`. Mode 1 `agnosticd/gcp/vars.yml` is out of scope.

**Inputs**

| Input | Value |
|-------|--------|
| Config directory | None in this repo. Shared AgnosticD v2 config `openshift-cluster` |
| Vars | `agnosticd/gcp/vars-multihub.yml` (T0), `agnosticd/gcp/vars-multihub-regional.yml` (T1 east) |
| Wrapper | `scripts/deploy.sh --mode multi-hub --tier global\|regional` |
| Cloud provider | GCP |
| Workloads | `ocp4_workload_cert_manager`, `ocp4_workload_authentication_htpasswd`, `ocp4_workload_rhacm`, `ocp4_workload_openshift_gitops`, `ocp4_workload_field_content`, `ocp4_workload_rhacm_observability_gcs`; Showroom on regional only |
| RHDP type | OCP dedicated (one cluster per GUID) |
| GUID | Not supplied |

```
AgnosticD Refactor Audit — Config: Mode 2 (artemis-edge-gcp-multihub)
──────────────────────────────────────────────────────
 #  Area                            Status  Notes
 1  Environment pre-flight          PASS    Python 3.12.14, podman 5.8.2, agnosticd-v2-virtualenv present, agd at ~/Development/agnosticd-v2/bin/agd. RQ-1 still open for per-platform correctives.
 2  Config file structure           SKIP    RQ-2. This repo is a vars overlay on openshift-cluster, not ansible/configs/<name>/. Mode 2 is four GUIDs; RHDP catalog items are one catalog item / one GUID. Do not collapse T0+T1.
 3  Workload role structure         WARN    Core workloads use FQCN from rhpds/core_workloads. ocp4_workload_rhacm_observability_gcs is not in this repo; it lives in agnosticd-v2/ansible/roles/ocp4_workload_rhacm_observability_gcs (meta, workload.yml, remove_workload.yml present). RQ-3 still open.
 4  agnosticd_user_info             SKIP    RQ-4. No agnosticd_user_info in this repo. Showroom mode_multi_hub is scripts/patch-showroom-mode.sh after provision, not user_info (vars comments already say so).
 5  Stop/start/status               PASS    scripts/stop.sh and start.sh delegate to agd stop|start|status per GUID. Mode 2 must be invoked four times (one GUID each). RQ-5 (AWS RHDP cost semantics) still open.
 6  Execution environment           SKIP    RQ-6. Wrapper runs agd (ansible-navigator EE). No custom EE in this repo.
 7  Multi-user configuration        N/A     Presenter-style demo: two htpasswd users, not N student namespaces. SNOs are Module 2, not AgnosticD.
 8  Secrets hygiene & tagging       PASS    Regional Mode 2 vars no longer commit adminPassword: admin (chart/values.yaml Mode 1 default still admin — discovery). Global Hub cloud_tags include hub-tier: global. Secrets dir is outside git (~/Development/agnosticd-v2-secrets). Remaining: no .yamllint under agnosticd/gcp/; spokeProvisioning.clusters: [] Helm coalesce is a documented discovery.
──────────────────────────────────────────────────────
 Result: 2 PASS, 3 SKIP (research pending), 1 WARN, 1 N/A, 0 FAIL after in-repo remediations
 Priority remaining (discoveries, not this bar): .yamllint under agnosticd/gcp/; Helm empty-list coalesce; four-GUID vs one catalog item (architecture, documented only); values.yaml Mode 1 adminPassword.
```

## Area notes

### 1. Environment pre-flight

Checked on the audit host. `onboard.yml` already requires Python 3.12 and podman. RQ-1: [agnosticd-refactor research-questions.md](https://github.com/rhpds/rhdp-skills-marketplace) RQ-1 remains open.

### 2. Config file structure

`config: openshift-cluster` in both Mode 2 vars files. `onboard.yml` copies them to `agnosticd-v2-vars/artemis-edge-gcp-multihub.yml` and `artemis-edge-gcp-multihub-regional.yml`. This host’s `agnosticd-v2-vars/` had only the Mode 1 copy at audit time.

Largest RHDP gap: one catalog item equals one GUID; Mode 2 is four provisions. Architecture capture only — this issue does not merge clusters.

### 3. Workload role structure

`ocp4_workload_rhacm_observability_gcs` path on this machine:

`/home/vpcuser/Development/agnosticd-v2/ansible/roles/ocp4_workload_rhacm_observability_gcs`

Files: `meta/main.yml`, `defaults/main.yml`, `tasks/main.yml`, `tasks/workload.yml`, `tasks/remove_workload.yml`. Destroy path exists. Role is not vendored in artemis-edge-acm-demo.

### 4. agnosticd_user_info

Showroom Antora `mode_multi_hub` is injected by `scripts/patch-showroom-mode.sh` after `agd provision`. RQ-4 SKIP.

### 5. Stop / start / status

`./scripts/deploy.sh --stop|--start|--status --mode multi-hub --tier {global|regional} --guid <GUID>`. Operators must pass each of the four GUIDs. RQ-5 SKIP.

### 6. Execution environment

`deploy.sh` `cd`s to agnosticd-v2 and runs `./bin/agd`. RQ-6 SKIP.

### 7. Multi-user

`ocp4_workload_authentication_htpasswd_user_count: 2`. Not an N-student lab.

### 8. Secrets and tags

- GCP secrets: `agnosticd-v2-secrets/` (outside this git repo). `scripts/generate-secrets.sh` writes `secrets-<account>.yml`.
- FAIL: `adminPassword: admin` in `agnosticd/gcp/vars-multihub-regional.yml` Helm `hubBrokers`.
- FAIL/gap: Global Hub `cloud_tags` lack `hub-tier: global` (regional already has `hub-tier: regional`).
- Discovery (not fixed): Helm `spokeProvisioning.clusters: []` may coalesce to chart defaults; `values.yaml` still has workshop `admin` for Mode 1.

## Remediations in this issue

Named by `.repo-governor/acceptance/77.json`: MODE2.md catalog + observability path; Global Hub `hub-tier: global`; drop `adminPassword: admin` from regional Mode 2 vars.
