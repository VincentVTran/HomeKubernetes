helm repo add metallb https://metallb.github.io/metallb
helm repo update
kubectl create namespace metallb-system
helm install metallb metallb/metallb --namespace metallb-system --values ./metallb-helm-values.yaml
kubectl apply -f ./config.yaml