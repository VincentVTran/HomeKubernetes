helm upgrade prometheus prometheus-community/prometheus \
    --namespace prometheus \
    --values prometheus-values.yaml