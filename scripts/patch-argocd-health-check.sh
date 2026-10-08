#!/usr/bin/env bash
# patch-argocd-health-check.sh — ArgoCD health checks & ApplicationSet controller
#
# 1. Application health check: required for App-of-Apps sync-wave ordering.
#    ArgoCD treats child Applications as Progressing until fully Healthy.
# 2. ApplicationSet health check (#169): always reports Healthy.  The
#    artemis-edge-workloads ApplicationSet is intentionally unbound per
#    Option C / #48 — it must never stall the sync at wave 5.
# 3. ApplicationSet controller enablement (#169): the OpenShift GitOps
#    operator does not start the controller unless spec.applicationSet has
#    resource requests.  Without the controller, ApplicationSet.status stays
#    null and ArgoCD reports Progressing indefinitely.
#
# Health checks are set via spec.resourceHealthChecks on the ArgoCD CR
# (not by patching argocd-cm directly, which the operator reverts).
set -euo pipefail

NAMESPACE="${ARGOCD_NAMESPACE:-openshift-gitops}"
ARGOCD_CR="${ARGOCD_CR_NAME:-openshift-gitops}"

# ── 1. Patch ArgoCD CR with health checks ────────────────────────────────

echo "[1/2] Patching ArgoCD CR '$ARGOCD_CR' with resourceHealthChecks..."

oc patch argocd "$ARGOCD_CR" -n "$NAMESPACE" --type merge -p '
{
  "spec": {
    "resourceHealthChecks": [
      {
        "group": "argoproj.io",
        "kind": "Application",
        "check": "hs = {}\nhs.status = \"Progressing\"\nhs.message = \"\"\nif obj.status ~= nil then\n  if obj.status.health ~= nil then\n    hs.status = obj.status.health.status\n    if obj.status.health.message ~= nil then\n      hs.message = obj.status.health.message\n    end\n  end\nend\nreturn hs"
      },
      {
        "group": "argoproj.io",
        "kind": "ApplicationSet",
        "check": "hs = {}\nhs.status = \"Healthy\"\nhs.message = \"ApplicationSet is healthy\"\nreturn hs"
      }
    ]
  }
}'

echo "  ArgoCD CR patched with health checks."

# ── 2. Enable ApplicationSet controller ──────────────────────────────────

echo "[2/2] Ensuring ApplicationSet controller is enabled on ArgoCD CR '$ARGOCD_CR'..."

CURRENT=$(oc get argocd "$ARGOCD_CR" -n "$NAMESPACE" \
  -o jsonpath='{.spec.applicationSet.resources.requests.cpu}' 2>/dev/null || true)

if [[ -z "$CURRENT" ]]; then
  oc patch argocd "$ARGOCD_CR" -n "$NAMESPACE" --type merge -p '
{
  "spec": {
    "applicationSet": {
      "resources": {
        "limits":   { "cpu": "1",    "memory": "1Gi"   },
        "requests": { "cpu": "250m", "memory": "512Mi" }
      }
    }
  }
}'
  echo "  ArgoCD CR patched — ApplicationSet controller will start."
else
  echo "  ApplicationSet controller already configured (cpu request: $CURRENT). Skipping."
fi

echo ""
echo "Done.  ArgoCD will now:"
echo "  - Wait for child Applications to be Healthy before proceeding to the next sync wave."
echo "  - Treat all ApplicationSets as Healthy (unbound ApplicationSet won't stall)."
echo "  - Run the ApplicationSet controller deployment."
