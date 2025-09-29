helm repo add gloo https://storage.googleapis.com/solo-public-helm
helm repo update

# Install Gloo Gateway using Helm with the custom values.yaml
helm install gloo gloo/gloo \
    --namespace gloo-system \
    --create-namespace \
    --values ./gloogateway-values.yaml
