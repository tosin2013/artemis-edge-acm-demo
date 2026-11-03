# Constitution — artemis-edge-acm-demo

> PLAYBOOK-infra section 2 principles + project-specific rules.
> Approved by: ___ (human)

## Infra principles (from PLAYBOOK-infra)

1. **Git is the source of truth.** Desired state lives in this repo and reaches
   clusters through GitOps (ArgoCD) or a declared AgnosticD playbook run. No
   hand edits with `oc edit`/`kubectl apply` that are not also in git. Drift is
   a bug.

2. **Declarative and idempotent.** Applying twice gives the same result as
   applying once. Helm renders are deterministic. AgnosticD workloads are
   re-runnable.

3. **Least privilege.** Every ServiceAccount, Role and operator gets only what
   it needs. No new `cluster-admin` bindings without a written reason in the
   spec. Workloads run under the default restricted SCC unless the spec
   justifies otherwise.

4. **No secrets in git.** Not in values files, not in AgnosticD vars, not in
   examples. Secrets flow through `agnosticd-v2-secrets/` (outside the repo),
   `generate-secrets.sh`, or `generate-tls.sh`. A secret scanner runs in CI.

5. **Reversible changes.** Every change has a rollback: revert the commit and
   let GitOps sync, or a documented `agd destroy` / `helm rollback` /
   `teardown.sh` step. Destructive steps (CRD removal, PV deletion, namespace
   deletion) need explicit human approval in the spec.

6. **Teardown is part of done.** Whatever the change creates, the repo can
   remove, and a teardown run proves nothing is left behind (namespaces, CRs,
   GCP resources, ACM placements).

7. **Pinned versions.** Chart version, `appVersion` (AMQ 7.14.1), operator
   channels and `startingCSV`, image digests/tags, collection versions: pinned,
   and bumped only on purpose. `values-gcp.yaml` pins instance types and
   storage classes.

8. **Setup is declared, not remembered.** The repo ships `onboard.yml` listing
   prerequisites, config, validation, quota checks and the deploy step.
   `bootstrap.sh` reads it at runtime. Any change to setup updates `onboard.yml`
   in the same PR. No step lives only in someone's head or laptop.

9. **Keep governance minimal.** Only gates that protect correctness and
   credentials. The evidence ladder (PLAYBOOK-infra section 5) is the quality
   bar; additional process only when it catches real bugs.

## Project-specific rules

10. **RHDP Field-Sourced Content pattern.** This repo is a Helm chart consumed
    by AgnosticD `ocp4_workload_field_content`. The chart root is the repo root.
    Mechanism 1 (Helm templates) is always active; Mechanism 4 (fleet-gitops)
    activates only in Mode 2. Mechanisms 2 (acm/) and 3 (ztp/) are reference
    only.

11. **Helm is the primary delivery.** All cluster state flows through `helm
    template` (rendered by ArgoCD). New workloads go in `templates/`, not as
    raw manifests applied outside the chart.

12. **AgnosticD v2 for provisioning.** Cluster lifecycle (create, destroy,
    start, stop) uses `agd provision`/`agd destroy` with vars from
    `agnosticd/gcp/`. The `scripts/deploy.sh` wrapper composes GUIDs and tiers.
    No direct `openshift-install` or Terraform.

13. **OpenEnv sandbox model.** Each deployment targets a GCP OpenEnv sandbox
    (`openenv-<SANDBOX>`, `<SANDBOX>.gcp.redhatworkshops.io`). Sandbox IDs are
    5 characters. Mode 2 composes GUIDs as `{tier}-{sandbox}`.

14. **SNOs are student-created.** AgnosticD provisions ACM hubs only. SNO edge
    clusters are created by students in Module 2 via `deploy-spokes.sh`. Never
    list SNO ClusterDeployments in Helm values or AgnosticD vars.

15. **Mode 2 tier ordering.** Global Hub (T0) must be provisioned before any
    regional hub (T1). Regional hubs can be parallelized after T0 is up.
    `import-managed-hubs.sh` runs after all T1 hubs are ready.

16. **No secrets in the model's context.** The AI (controller or worker) never
    holds cluster credentials, GCP keys, pull secrets, or Keycloak secrets.
    Those flow through `generate-secrets.sh`, `agnosticd-v2-secrets/`, and the
    human's shell.

17. **Pre-flight before provision.** Before any `agd provision`, verify that
    secrets are populated (not placeholders), GCP key PEM is valid, gcloud is
    authenticated, and `bootstrap.sh --check-only` passes. A failed provision
    leaves stale state on the bastion that blocks re-provision (see ROADMAP.md
    bugs B1-B3). Catch it before it burns 50 minutes of compute.

18. **Record what broke.** Per PLAYBOOK-infra section 9 step 12: when a deploy
    fails, document the root cause in ROADMAP.md, update the spec/plan/tasks
    with the fix, and add a pre-flight check so it cannot recur silently.

19. **Skills inform, never replace gates.** Skills from
    [tosin2013/rhel-devops-skills-cli](https://github.com/tosin2013/rhel-devops-skills-cli)
    (`agnosticd`, `agnosticd-deploy-test`, `static-validation`,
    `field-sourced-content`, `onboard`) are installed to `~/.cursor/skills/`
    and inform the AI about tooling patterns. They never replace the evidence
    ladder artifacts or the human review gates. The `onboard` skill drives
    the repeatability check (PLAYBOOK-infra section 5) and validates
    `onboard.yml` correctness — any hand step it finds is a bug.
