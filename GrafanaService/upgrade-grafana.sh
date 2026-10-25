#!/bin/bash
# Applies changes to grafana-values.yaml and ./dashboards (or a new chart version in ./chart-version). Run
# ../OtelService/verify-telemetry.sh after.
# Pass --kube-context <ctx> to target another cluster; KUBECONFIG is honoured as usual.
set -euo pipefail
cd "$(dirname "$0")"
HELM=(helm); [[ "${1:-}" == --kube-context ]] && HELM+=(--kube-context "$2")
VERSION=$(<chart-version)   # the pinned chart version, shared with the other script in this folder

helm repo update grafana

"${HELM[@]}" upgrade grafana grafana/grafana \
  --version "$VERSION" \
    --wait --timeout 5m \
  --namespace grafana \
  --values ./grafana-values.yaml \
  --set-file dashboards.portal.applicant-portal.json=./dashboards/applicant-portal.json
