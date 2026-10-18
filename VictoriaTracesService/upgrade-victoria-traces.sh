#!/bin/bash
# Applies changes to victoria-traces-values.yaml (or a new pinned --version) to the running release.
# Pass --kube-context <ctx> to target another cluster; KUBECONFIG is honoured as usual.
set -euo pipefail
cd "$(dirname "$0")"
HELM=(helm); [[ "${1:-}" == --kube-context ]] && HELM+=(--kube-context "$2")

helm repo update vm

"${HELM[@]}" upgrade victoria-traces vm/victoria-traces-single \
    --version 0.1.11 \
    --namespace victoria-traces \
    --values ./victoria-traces-values.yaml
