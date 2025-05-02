# For Ubuntu
sudo curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='--flannel-backend=none --disable-network-policy' sh -s - --resolv-conf /run/systemd/resolve/resolv.conf

# For non-Ubuntu
# sudo curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='--flannel-backend=none --disable-network-policy' sh -

export KUBECONFIG=~/.kube/config
export MASTER_IP=192.168.88.206
export MASTER_PORT=6443

mkdir ~/.kube 2> /dev/null
sudo k3s kubectl config view --raw > "$KUBECONFIG"
chmod 600 "$KUBECONFIG"

# Installing Cilium via Helm: https://github.com/cilium/cilium/blob/main/install/kubernetes/cilium/values.yaml
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium --version 1.17.3 \
   --namespace kube-system \
   --set ipam.operator.clusterPoolIPv4PodCIDRList="10.42.0.0/16" \
   --set l2announcements.enabled=true \
   --set k8sClientRateLimit.qps=50 \
   --set k8sClientRateLimit.burst=200 \
   --set kubeProxyReplacement=true \
   --set k8sServiceHost=$MASTER_IP \
   --set k8sServicePort=$MASTER_PORT \
   --set externalIPs.enabled=true

# https://github.com/k3s-io/k3s/issues/5349
# Stop and disable UFW right away
sudo ufw disable                    # Stops the firewall service immediately :contentReference[oaicite:0]{index=0}

# Prevent UFW from starting at system boot
sudo systemctl disable ufw.service

# Flush all current iptables rules
sudo iptables -F              # Flushes all rules in the filter table :contentReference[oaicite:4]{index=4}
sudo iptables -X              # Deletes any user-defined chains
sudo iptables -t nat -F       # Flushes NAT table rules
sudo iptables -t nat -X       # Deletes NAT custom chains
sudo iptables -t mangle -F    # Flushes mangle table rules
sudo iptables -t mangle -X    # Deletes mangle custom chains