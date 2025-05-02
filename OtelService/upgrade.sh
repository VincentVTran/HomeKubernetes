# Install Prometheus using Helm with the custom values.yaml
helm upgrade otel-collector open-telemetry/opentelemetry-collector \
    --namespace otel \
    --create-namespace \
    --set podAnnotations.restartTimestamp=$(date +%s) \
    --values ./otel-values.yaml