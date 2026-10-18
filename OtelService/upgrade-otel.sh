#!/bin/bash
# Applies changes to the values files (or a new pinned VERSION) to both Collectors. Run ./verify-telemetry.sh after.
# Pass --kube-context <ctx> to target another cluster; KUBECONFIG is honoured as usual.
set -euo pipefail
cd "$(dirname "$0")"
HELM=(helm); [[ "${1:-}" == --kube-context ]] && HELM+=(--kube-context "$2")
VERSION=0.175.0

helm repo update open-telemetry

"${HELM[@]}" upgrade otel-gateway open-telemetry/opentelemetry-collector \
    --version "$VERSION" \
    --namespace otel \
    --values ./otel-gateway-values.yaml

"${HELM[@]}" upgrade otel-agent open-telemetry/opentelemetry-collector \
    --version "$VERSION" \
    --namespace otel \
    --values ./otel-agent-values.yaml
