#!/bin/bash

# Variables — update these
REMOTE_USER="vincent-tran"
REMOTE_HOST="192.168.88.206"

REMOTE_K3S_CONFIG="/etc/rancher/k3s/k3s.yaml"
LOCAL_KUBECONFIG="$HOME/.kube/config"

# Ask for the remote sudo password
read -s -p "Enter sudo password for ${REMOTE_USER}@${REMOTE_HOST}: " REMOTE_SUDO_PASS
echo ""

# Ensure ~/.kube directory exists
mkdir -p "$HOME/.kube"

# Run ssh, pipe in the sudo password to cat the file
ssh "${REMOTE_USER}@${REMOTE_HOST}" "echo '${REMOTE_SUDO_PASS}' | sudo -S cat ${REMOTE_K3S_CONFIG}" > "$LOCAL_KUBECONFIG"

# Replace localhost in config with actual IP/hostname if needed
sed -i "s/127.0.0.1/${REMOTE_HOST}/g" "$LOCAL_KUBECONFIG"
sed -i "s/localhost/${REMOTE_HOST}/g" "$LOCAL_KUBECONFIG"

echo "Kubeconfig successfully copied to $LOCAL_KUBECONFIG"