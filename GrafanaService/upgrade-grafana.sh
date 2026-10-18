#!/bin/bash
# Applies changes to grafana-values.yaml and ./dashboards (or a new pinned VERSION). Run
# ../OtelService/verify-telemetry.sh after.
# Pass --kube-context <ctx> to target another cluster; KUBECONFIG is honoured as usual.
set -euo pipefail
cd "$(dirname "$0")"
HELM=(helm); [[ "${1:-}" == --kube-context ]] && HELM+=(--kube-context "$2")
VERSION=10.0.0

helm repo update grafana

"${HELM[@]}" upgrade grafana grafana/grafana \
  --version "$VERSION" \
  --namespace grafana \
  --values ./grafana-values.yaml \
  --set-file dashboards.portal.id-verification-portal.json=./dashboards/id-verification-portal.json
