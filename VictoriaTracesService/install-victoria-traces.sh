#!/bin/bash
# VictoriaTraces (single node): the trace store. The gateway Collector writes to it; Grafana reads its Jaeger API.
# Pass --kube-context <ctx> to target another cluster; KUBECONFIG is honoured as usual.
set -euo pipefail
cd "$(dirname "$0")"
HELM=(helm); [[ "${1:-}" == --kube-context ]] && HELM+=(--kube-context "$2")
VERSION=$(<chart-version)   # the pinned chart version, shared with the other script in this folder

helm repo add vm https://victoriametrics.github.io/helm-charts
helm repo update vm

"${HELM[@]}" install victoria-traces vm/victoria-traces-single \
    --version "$VERSION" \
    --namespace victoria-traces \
    --create-namespace \
    --values ./victoria-traces-values.yaml
