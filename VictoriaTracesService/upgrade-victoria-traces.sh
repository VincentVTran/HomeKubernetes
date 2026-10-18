#!/bin/bash
# Applies changes to victoria-traces-values.yaml (or a new chart version in ./chart-version) to the running release.
# Pass --kube-context <ctx> to target another cluster; KUBECONFIG is honoured as usual.
set -euo pipefail
cd "$(dirname "$0")"
HELM=(helm); [[ "${1:-}" == --kube-context ]] && HELM+=(--kube-context "$2")
VERSION=$(<chart-version)   # the pinned chart version, shared with the other script in this folder

helm repo update vm

"${HELM[@]}" upgrade victoria-traces vm/victoria-traces-single \
    --version "$VERSION" \
    --wait --timeout 5m \
    --namespace victoria-traces \
    --values ./victoria-traces-values.yaml
