#!/usr/bin/env bash
# patch-argocd-health-check.sh
# Adds an Application health check to argocd-cm so that ArgoCD
# treats child Applications as Progressing until they are fully Healthy.
# This is required for the App-of-Apps pattern to enforce sync-wave ordering.
set -euo pipefail

NAMESPACE="${ARGOCD_NAMESPACE:-openshift-gitops}"

echo "Patching argocd-cm in namespace $NAMESPACE with Application health check..."

oc patch configmap argocd-cm -n "$NAMESPACE" --type merge -p '
{
  "data": {
    "resource.customizations.health.argoproj.io_Application": "hs = {}\nhs.status = \"Progressing\"\nhs.message = \"\"\nif obj.status ~= nil then\n  if obj.status.health ~= nil then\n    hs.status = obj.status.health.status\n    if obj.status.health.message ~= nil then\n      hs.message = obj.status.health.message\n    end\n  end\nend\nreturn hs\n"
  }
}'

echo "Patched argocd-cm successfully."
echo "ArgoCD will now wait for child Applications to be Healthy before proceeding to the next sync wave."
