helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

# Install Prometheus using Helm with the custom values.yaml
helm install otel-collector open-telemetry/opentelemetry-collector \
    --namespace otel \
    --create-namespace \
    --values ./otel-values.yaml