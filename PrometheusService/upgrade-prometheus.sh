helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Pinned so upgrades are deliberate. Before bumping, check the new chart's
# default scrapeConfigs are still all disabled in prometheus-values.yaml.
helm upgrade prometheus prometheus-community/prometheus \
    --namespace prometheus \
    --version 29.37.0 \
    --values prometheus-values.yaml
