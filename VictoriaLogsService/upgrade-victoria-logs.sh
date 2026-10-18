#!/bin/bash
# Applies changes to victoria-logs-values.yaml (or a new pinned --version) to the running release.
# Pass --kube-context <ctx> to target another cluster; KUBECONFIG is honoured as usual.
set -euo pipefail
cd "$(dirname "$0")"
HELM=(helm); [[ "${1:-}" == --kube-context ]] && HELM+=(--kube-context "$2")

helm repo update vm

"${HELM[@]}" upgrade victoria-logs vm/victoria-logs-single \
    --version 0.13.10 \
    --namespace victoria-logs \
    --values ./victoria-logs-values.yaml
