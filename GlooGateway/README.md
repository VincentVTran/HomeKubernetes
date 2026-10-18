#### Instruction
To deploy the routes, run:
`kubectl apply -f ./routes`

#### Internal routes (home network only, http://192.168.2.4)
| Path | Goes to |
|---|---|
| `/prometheus` | Prometheus |
| `/grafana` | Grafana |
| `/logs` | VictoriaLogs' web UI (read API only: `/logs/select/...` is rewritten to `/select/...`; `/logs` redirects to `/logs/select/vmui/`) |

These are in `routes/internal-routes.yaml` (label `exposure: internal`), which only the LAN gateway serves. The ngrok tunnel reaches
the external gateway, which serves only `exposure: external` routes.
