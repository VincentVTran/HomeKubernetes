helm repo add metallb https://metallb.github.io/metallb
helm repo update
kubectl create namespace metallb-system
helm install metallb metallb/metallb --namespace metallb-system
kubectl wait --for=condition=ready pod --all -n metallb-system --timeout=300s
kubectl apply -f ./config.yaml
