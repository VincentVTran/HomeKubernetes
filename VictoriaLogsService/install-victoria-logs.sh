#!/bin/bash
# VictoriaLogs (single node): the log store. The gateway Collector writes to it; Grafana reads it.
# Pass --kube-context <ctx> to target another cluster; KUBECONFIG is honoured as usual.
set -euo pipefail
cd "$(dirname "$0")"
HELM=(helm); [[ "${1:-}" == --kube-context ]] && HELM+=(--kube-context "$2")
VERSION=$(<chart-version)   # the pinned chart version, shared with the other script in this folder

helm repo add vm https://victoriametrics.github.io/helm-charts
helm repo update vm

"${HELM[@]}" install victoria-logs vm/victoria-logs-single \
    --version "$VERSION" \
    --wait --timeout 5m \
    --namespace victoria-logs \
    --create-namespace \
    --values ./victoria-logs-values.yaml
