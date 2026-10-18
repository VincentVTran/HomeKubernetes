#!/bin/bash
# OpenTelemetry Collectors in namespace `otel`: the gateway (Deployment, receives OTLP, writes to VictoriaLogs and
# VictoriaTraces) and the agent (DaemonSet, collects every pod's console logs). Install the stores first, then run
# ./verify-telemetry.sh.
# Pass --kube-context <ctx> to target another cluster; KUBECONFIG is honoured as usual.
set -euo pipefail
cd "$(dirname "$0")"
HELM=(helm); [[ "${1:-}" == --kube-context ]] && HELM+=(--kube-context "$2")
VERSION=$(<chart-version)   # the pinned chart version, shared with the other script in this folder

helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update open-telemetry

"${HELM[@]}" install otel-gateway open-telemetry/opentelemetry-collector \
    --version "$VERSION" \
    --namespace otel \
    --create-namespace \
    --values ./otel-gateway-values.yaml

"${HELM[@]}" install otel-agent open-telemetry/opentelemetry-collector \
    --version "$VERSION" \
    --namespace otel \
    --values ./otel-agent-values.yaml
