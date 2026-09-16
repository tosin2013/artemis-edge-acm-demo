# fleet-gitops — Mode 2 ACM hub-of-hubs + regional AMQ hubs
#
# Push: Global Hub Argo CD → three regional ACM hubs (`applicationsets/hubs.yaml`).
# Pull: each regional hub ApplicationSet → student SNOs (`hubs/base/applicationset-amq.yaml`).
#       Needs OpenShift GitOps Operator 1.9.0+ (`argocd.argoproj.io/skip-reconcile`).
# Platform: OperatorPolicy + UWM on sites (pushed onto each regional hub).
# Site addresses: `amq/base/broker.yaml` uses `brokerProperties` (AMQ 7.12;
# `ActiveMQArtemisAddress` / `ActiveMQArtemisSecurity` are deprecated).
#
# Region Git tags `fleet-east` / `fleet-central` / `fleet-west` are the promotion
# boundary (`hubs/overlays/<region>` patches `targetRevision`).
#
# Apply on Global Hub after the three regional hubs are imported and labelled
# `hub-tier=regional`, `region=east|central|west`.
#
# Layout:
#   applicationsets/hubs.yaml          GH → regional hub config
#   hubs/base/                         pull ApplicationSet, GitOpsCluster, site policies
#   hubs/overlays/{east,central,west}/
#   amq/base/                          site ActiveMQArtemis (cookie-cutter)
#   platform/policies/                 OperatorPolicy sources
#   platform/placements/all-hubs.yaml  GH placement for managed hubs
