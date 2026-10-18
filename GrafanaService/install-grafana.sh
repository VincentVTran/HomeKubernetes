#!/bin/bash
# Grafana in namespace `grafana`: data sources for Prometheus, VictoriaLogs and VictoriaTraces, and the dashboards in
# ./dashboards. Needs the `grafana-admin` Secret first (see README.md). Run ../OtelService/verify-telemetry.sh after.
# Pass --kube-context <ctx> to target another cluster; KUBECONFIG is honoured as usual.
set -euo pipefail
cd "$(dirname "$0")"
HELM=(helm); KUBECTL=(kubectl)
[[ "${1:-}" == --kube-context ]] && { HELM+=(--kube-context "$2"); KUBECTL+=(--context "$2"); }
VERSION=$(<chart-version)   # the pinned chart version, shared with the other script in this folder

if ! "${KUBECTL[@]}" get secret grafana-admin --namespace grafana >/dev/null 2>&1; then
  echo "Create the admin Secret first (see README.md), e.g.:" >&2
  echo "  kubectl create namespace grafana" >&2
  echo "  kubectl create secret generic grafana-admin --namespace grafana --from-literal=admin-user=admin --from-literal=admin-password=\"\$(openssl rand -base64 24)\"" >&2
  exit 1
fi

helm repo add grafana https://grafana.github.io/helm-charts
helm repo update grafana

"${HELM[@]}" install grafana grafana/grafana \
  --version "$VERSION" \
  --namespace grafana \
  --values ./grafana-values.yaml \
  --set-file dashboards.portal.id-verification-portal.json=./dashboards/id-verification-portal.json
