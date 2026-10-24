# Setting up kubernetes cluster using k3s
## To install control plane
- Go to the /ClusterSetupScripts/master_node_setup_k3s_cilium.sh file.
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

# Setting up L2 announcement for LAN external IPs
- `kubectl apply -f ./ClusterSetupScripts/CiliumConfig/`

# Setting up bare-metal load balancing (alternative)
## Installing Metallb
- `sudo ./MetallbConfig/install-metallb.sh`

# Installing Home NGINX Into Cluster
## To build
- `make build-image`
## To deploy app to cluster
- `make deploy` to install the metal lb configurations

# Public access (Cloudflare Tunnel)
The portal is reached from the internet through a Cloudflare Tunnel to Gloo's external gateway; nothing is opened on the LAN.
Setup, adding hostnames, checking it (`./CloudflareTunnel/verify-tunnel.sh`) and the runbook for moving off ngrok (and for
pointing the Wix domain at Cloudflare) are in `CloudflareTunnel/README.md`. ngrok (`NgrokTunnel/`) runs alongside until that
runbook retires it.

# Logs and traces (OpenTelemetry)
Install in this order, then verify (each folder's README has the details):
```
./VictoriaLogsService/install-victoria-logs.sh       # log store: 14 days / 20 GiB cap
./VictoriaTracesService/install-victoria-traces.sh   # trace store: 7 days / 10 GiB cap
./OtelService/install-otel.sh                        # gateway + agent Collectors
./GrafanaService/install-grafana.sh                  # data sources + portal dashboard (create the grafana-admin Secret first)
./OtelService/verify-telemetry.sh                    # sends a log and a span, finds both in the stores and through Grafana
```
Apps send OTLP to `http://otel-gateway.otel.svc.cluster.local:4318`; every pod's console logs are collected automatically.
To find a request by the reference code the portal shows, see `GrafanaService/README.md`.
