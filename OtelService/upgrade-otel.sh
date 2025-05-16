# Install Prometheus using Helm with the custom values.yaml
helm upgrade otel-collector open-telemetry/opentelemetry-collector \
    --namespace otel \
    --create-namespace \
    --values ./otel-values.yaml