# Setting up kubernetes cluster using k3s
## To install control plane
- Go to the /Scripts/master_node_setup_k3s_cilium.sh file.
- Execute the script using `./master_node_setup_k3s_cilium.sh`

## To add node to dataplane
- To get token data: sudo cat /var/lib/rancher/k3s/server/node-token
- To get control plane IP data: ifconfig
```
export TOKEN_DATA=
export CONTROL_PLANE_IP=
curl -sfL https://get.k3s.io | K3S_URL=https://${CONTROL_PLANE_IP}:6443 K3S_TOKEN=${TOKEN_DATA} sh -
```

## Getting Kube Config
- `sudo cat /etc/rancher/k3s/k3s.yaml` (Upload this to $HOME/.kube/config)

# Setting up bare-metal load balancing
## Installing Metallb
- `sudo ./MetallbConfig/install-metallb.sh`
- `kubectl apply -f ./MetallbConfig/` to install the metal lb configurations

# Installing Home NGINX Into Cluster
## To build
- `make build-image`
## To deploy app to cluster
- `make deploy` to install the metal lb configurations