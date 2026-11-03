# ROADMAP

> Written as part of PLAYBOOK-infra adoption (section 9, step 3).
> Approved by: ___ (human)

## What the repo deploys

**Artemis Edge ACM Demo** (Helm chart `artemis-edge-acm-demo` v0.3.0, AMQ Broker 7.14.1).

A Field-Sourced Content Helm chart for the Red Hat Demo Platform (RHDP) that
demonstrates federated AMQ Broker messaging across RHACM-managed Single Node
OpenShift (SNO) edge clusters.

### Workloads delivered by the Helm chart (44 templates)

| Workload | Mode 1 | Mode 2 Global Hub | Mode 2 Regional Hub |
|----------|--------|--------------------|---------------------|
| AMQ Broker Operator | yes | no | yes |
| AMQ hub broker (hub-01) | yes | no | yes |
| Edge broker ACM policies | yes | no | yes |
| Keycloak OIDC | yes | no | yes |
| Showroom lab guide | yes | no | yes (east only) |
| Prometheus + Grafana | yes | no | yes |
| cert-manager | yes | yes | yes |
| OpenShift GitOps (ArgoCD) | yes | yes | yes |
| RHACM | yes | yes | yes |
| Multicluster Global Hub operator | no | yes | no |
| fleet-gitops ArgoCD Application | no | yes | no |
| Thanos Query (fleet AMQ metrics) | no | yes | no |

### Four delivery mechanisms

1. **Helm Chart Templates** (`templates/`) — always active, core delivery
2. **ACM ApplicationSet** (`acm/`) — reference only, not wired
3. **ZTP PolicyGenerator** (`ztp/`) — reference only, not wired
4. **Fleet GitOps** (`fleet-gitops/`) — Mode 2 only, push+pull Kustomize+ArgoCD

See `docs/delivery-mechanisms.md` for details.

## Where it deploys

**GCP only** (Azure has a values overlay but is not implemented).

| Mode | Clusters | GCP Regions |
|------|----------|-------------|
| Mode 1 (single-hub) | 1 ACM hub | us-east1 |
| Mode 2 (multi-hub) | 1 Global Hub + 3 regional ACM hubs | us-east1, us-east4, us-central1, us-west1 |

SNO edge clusters are created by students in Module 2 (never at provision time).

GCP resources per cluster: `n2-standard-16` workers, `n2-standard-8` SNOs,
`pd-ssd` storage. Mode 2 requires 132 N2 vCPUs + 4050 GiB SSD per region.

## How it syncs

### Provisioning

`bootstrap.sh` reads `onboard.yml` -> installs prerequisites -> clones
AgnosticD v2 -> `scripts/deploy.sh` -> `agd provision` (Ansible via
`ansible-navigator` in an Execution Environment container).

- Mode 1: one `agd provision` call
- Mode 2: four sequential `agd provision` calls (global, east, central, west),
  then `scripts/import-managed-hubs.sh` to register regional hubs with Global Hub

### GitOps (post-provision)

- **Mode 1:** ArgoCD on the hub renders this Helm chart directly.
- **Mode 2:**
  - ArgoCD on Global Hub **pushes** `fleet-gitops/` to 3 regional hubs
    via `fleet-gitops/applicationsets/hubs.yaml`
  - ArgoCD on each regional hub **pulls** to SNOs via
    `fleet-gitops/hubs/base/applicationset-amq.yaml`
  - Region Git tags (`fleet-east`, `fleet-central`, `fleet-west`) are the
    promotion boundary

### ACM policies

- OperatorPolicy delivers AMQ, UWM, and GitOps operators to managed clusters
- ConfigurationPolicy delivers broker CRs to SNOs
- Global Hub replicates policy compliance status from regional hubs

## What tests exist today

### CI (GitHub Actions)

| Workflow | What it does | Rung |
|----------|-------------|------|
| `helm-validate.yaml` | `helm lint` + `helm template` for 3 overlays (Mode 1, Mode 2 regional, Mode 2 global) | 1 (partial) |
| `showroom-gh-pages.yaml` | Antora build for lab guide preview | N/A |

### Manual validation

| Script/tool | What it checks |
|-------------|---------------|
| `scripts/validate-deployment.sh` | Post-deploy workload health |
| `scripts/validate-gcp-key.py` | GCP key PEM integrity |
| `bootstrap.sh --check-only` | Prerequisites + environment |

### Repo Governor

107 acceptance criteria in `.repo-governor/acceptance/*.json` — automated
checks for Helm template output, naming conventions, values schema, etc.
Run via `.repo-governor.json` configuration.

## Gaps (relative to PLAYBOOK-infra evidence ladder)

| Gap | PLAYBOOK-infra requirement | Current state |
|-----|---------------------------|---------------|
| No schema validation | Rung 1: `kubeconform` against OpenShift + operator CRD schemas | Only `helm lint` / `helm template` |
| No secret scanning in CI | Rung 1: `gitleaks` or equivalent | None |
| No OPA/Kyverno policy checks | Rung 1: `conftest` or `kyverno apply` | None |
| No `yamllint` in CI | Rung 1: `yamllint` | Available in dev mode only |
| No dry-run evidence | Rung 2: `kubectl apply --dry-run=server` | Not captured |
| No structured reconcile evidence | Rung 3: ArgoCD Synced/Healthy proof | `validate-deployment.sh` exists but output not saved as artifacts |
| No RBAC/security audit | Rung 4: `oc adm policy who-can`, image scan, SCC check | None |
| No teardown evidence | Rung 6: before/after resource lists | `teardown.sh` exists but no proof artifacts |
| No repeatability check | Deploy, teardown, redeploy on fresh targets | Never done formally |
| No `.specify/` directory | Constitution, specs, plans, tasks | None |
| No `VERIFY.md` | Per-spec checklist | None |
| No `docs/evidence/` | Artifacts per rung per spec | None |

## `onboard.yml` status

**Present and comprehensive** (502 lines). Covers:

- 11 prerequisites with per-OS install commands
- 8 setup steps (clone AgnosticD, agd setup, sync vars, secrets, TLS, Java build)
- 10 config prompts (mode, cloud, sandbox ID, domains, secrets)
- 16 validation checks (helm, TLS, AgnosticD, GCP auth, multi-hub vars)
- 8 quota checks (N2 vCPUs + SSD per region for Mode 2)
- Dev and prod modes
- Post-setup deploy instructions

`bootstrap.sh` reads it at runtime via Python 3 + PyYAML.

## Bugs found during spec 001 deploy (2026-10-29)

| # | Bug | Impact | Fix |
|---|-----|--------|-----|
| B1 | `generate-secrets.sh` leaves `ocp4_pull_secret` empty when `~/pull-secret.json` is missing at setup time | `openshift-install` fails with `pullSecret: Invalid value: "<Add Your Pull Secret here>"` | Add a validation check that the pull secret is populated in the secrets YAML, not just that the file exists |
| B2 | `bootstrap.sh` `run_setup_steps()` (line 438) uses `eval "$action"` in the current shell; `agd setup` does `cd`, which leaks to subsequent steps | `cp agnosticd/gcp/vars.yml ...` fails because cwd is now the agnosticd dir | Wrap eval in a subshell: `(eval "$action")` |
| B3 | Stale bastion state after a failed `openshift-install`: `agd destroy` removes GCP infra but not the install artifacts on a reused bastion | Re-provision skips `openshift-install` (thinks cluster exists), then fails at `kubeadmin-password` read | `deploy.sh` or `post-provision-multihub.sh` should clean the install directory on the bastion before retrying, or detect the missing `auth/` dir |
| B4 | `onboard.yml` has no validation check for pull secret content inside `secrets-openenv-gcp.yml` | Deploys proceed with a placeholder pull secret | Add a validation step: parse the secrets YAML and assert `ocp4_pull_secret` is valid JSON with an `auths` key |
| B5 | `agd` loads `secrets.yml` after `secrets-<account>.yml`, and the template still contains `ocp4_pull_secret: '<Add Your Pull Secret here>'` | The account file can be correct and the install still receives the placeholder | Put the real pull secret in `secrets.yml` as well, or stop shipping the placeholder key in the file that is loaded last |
| B6 | Mode 2 vars set east=`us-east4`, central=`us-central1`, west=`us-west1`, but every cluster's Infrastructure CR and every GCE instance in project `openenv-26j7t` is in `us-east1` | Regional hubs are not actually in separate GCP regions | Trace which var `agd` uses for `gcp_region` on the regional configs and reprovision those tiers |
| B7 | Argo CD validates every rendered API group before sync waves. `SkipDryRunOnMissingResource=true` does not skip that discovery | `field-content` stays OutOfSync / Missing on all four hubs, so `fleet-gitops` and `hub-config-*` are never created | `scripts/prime-field-content.sh`, called from `post-provision-multihub.sh` step 2b, applies the chart's Namespace, OperatorGroup, and Subscription documents and requests a sync of the Application |

## Optional skills decision (PLAYBOOK-infra section 7)

Per the [PLAYBOOK-infra section 7](https://raw.githubusercontent.com/tosin2013/invoice-exception-desk/refs/heads/main/docs/PLAYBOOK-infra.md),
the following skills from [tosin2013/rhel-devops-skills-cli](https://github.com/tosin2013/rhel-devops-skills-cli)
are selected for this repo:

| Skill | Why | Use at |
|-------|-----|--------|
| `agnosticd` | AgnosticD v2 vars, secrets wiring, install lifecycle — would have caught B1 and B3 | plan, tasks, review |
| `agnosticd-deploy-test` | End-to-end validation including stale bastion detection | rungs 3, 5, 6 |
| `static-validation` | Rung 1 offline checks: `kubeconform`, `gitleaks`, `yamllint`, `conftest` | implement, CI |
| `field-sourced-content` | RHDP Helm chart delivery pattern used by this repo | plan, tasks |
| `onboard` (aka `project-onboard`) | Reads `onboard.yml` manifests, validates environment, runs repeatability checks, generates `bootstrap.sh` for people without an agent — would have caught B2 (cd leak) and B4 (missing pull secret validation) | setup, repeatability check, bootstrap.sh generation |

Skills **not** selected (and why):
- `agnosticd-hub-student` — quotas already verified sufficient
- `patternizer` / `vp-*` — this repo uses field-sourced-content, not Validated Patterns
- `showroom` / `workshop-tester` — deferred until clusters are running (rung 5)
- `rhel-devops-auditor` — ROADMAP already written manually

## Roadmap items

### Near-term (this spec cycle)

1. **PLAYBOOK-infra adoption** — constitution, spec 001 (Mode 2 GCP deploy),
   evidence ladder, VERIFY.md. Sandbox `26j7t` is provisioned: 4 hubs up,
   regional hubs joined, field-content and hub-config apps Synced/Healthy.
2. **Fix bugs B1-B5** — pull secret validation and `secrets.yml` override,
   bootstrap.sh subshell fix, stale bastion cleanup, onboard.yml validation gap.
   Code fixes for B2 and B4 are in the repo. B5 is fixed in the local secrets
   file, which is not committed.
3. **Install selected skills** — installed to `~/.cursor/skills`:
   `agnosticd`, `agnosticd-deploy-test`, `static-validation`,
   `field-sourced-content`, `project-onboard`.
4. **Rung 1 hardening** — add `kubeconform`, `yamllint`, `gitleaks` to CI
   alongside existing `helm lint`/`helm template` (use `static-validation`
   skill).

### Future

5. **Rung 4 automation** — RBAC diff script, image scan with `trivy`/`grype`,
   SCC validation script.
6. **Repeatability check script** — automated deploy/teardown/redeploy with
   evidence capture.
7. **Azure support** — `values-azure.yaml` exists but `agnosticd/azure/` vars
   are missing; `docs/azure-status.md` says not implemented.
8. **Consolidate test tooling** — unify repo-governor acceptance checks with
   rung 1 static validation.
