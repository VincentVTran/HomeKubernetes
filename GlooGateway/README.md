#### Instruction
To deploy the routes, run:
`kubectl apply -f ./routes`

#### Internal routes (home network only, http://192.168.2.4)
| Path | Goes to |
|---|---|
| `/prometheus` | Prometheus |
| `/grafana` | Grafana |
| `/logs` | VictoriaLogs' web UI (read API only: `/logs/select/...` is rewritten to `/select/...`; `/logs` redirects to `/logs/select/vmui/`) |

These are in `routes/internal-routes.yaml` (label `exposure: internal`), which only the LAN gateway serves.

#### External routes (public, through a tunnel)
The public tunnel reaches the external gateway (`external-gateway-proxy`, ClusterIP only), which serves only `exposure: external`
routes: `routes/external-routes.yaml`, which sends its domains to the ID verification portal.
The tunnel is the Cloudflare Tunnel (`../CloudflareTunnel`), for `rental.vtranlabs.com`.

Never give an internal service an `exposure: external` route: everything on the external gateway is on the internet.
