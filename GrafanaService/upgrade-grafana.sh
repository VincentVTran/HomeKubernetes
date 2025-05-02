helm upgrade grafana grafana/grafana \
  --namespace grafana \
  --create-namespace \
  --values grafana-values.yaml