# Upgrade Gloo Gateway using Helm with the custom values.yaml
helm upgrade gloo gloo/gloo \
    --namespace gloo-system \
    --create-namespace \
    --values ./gloogateway-values.yaml
