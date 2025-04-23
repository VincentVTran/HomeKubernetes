export MASTER_IP=192.168.88.212
export MASTER_PORT=6443

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='--flannel-backend=none --disable-network-policy' sh -

export KUBECONFIG=~/.kube/config

mkdir ~/.kube 2> /dev/null
sudo k3s kubectl config view --raw > "$KUBECONFIG"
chmod 600 "$KUBECONFIG"

# Installing Cilium via Helm
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium --version 1.17.3 \
   --namespace kube-system \

helm upgrade cilium cilium/cilium --version 1.17.3 \
   --namespace kube-system \
   --reuse-values \
   --set l2announcements.enabled=true \
   --set k8sClientRateLimit.qps=50 \
   --set k8sClientRateLimit.burst=200 \
   --set kubeProxyReplacement=true \
   --set k8sServiceHost=$MASTER_IP \
   --set k8sServicePort=$MASTER_PORT \
   --set externalIPs.enabled=true
