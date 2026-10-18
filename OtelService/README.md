### Documentation
https://opentelemetry.io/docs/collector/ and the chart: https://github.com/open-telemetry/opentelemetry-helm-charts/tree/main/charts/opentelemetry-collector

### What runs here (namespace `otel`)
Two OpenTelemetry Collectors from chart `open-telemetry/opentelemetry-collector` 0.175.0, contrib image 0.161.0:

| Release | Kind | Does | Values |
|---|---|---|---|
| `otel-gateway` | Deployment (1) | Receives OTLP from apps and the agent; the only writer to the stores | `otel-gateway-values.yaml` |
| `otel-agent` | DaemonSet (`otel-agent-agent`) | Reads every pod's console log on the node, forwards to the gateway | `otel-agent-values.yaml` |

- Apps send to `http://otel-gateway.otel.svc.cluster.local:4318` (OTLP/HTTP) or `otel-gateway.otel.svc.cluster.local:4317`
  (OTLP/gRPC), e.g. `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-gateway.otel.svc.cluster.local:4318`.
- Logs go to VictoriaLogs (`../VictoriaLogsService`), traces to VictoriaTraces (`../VictoriaTracesService`), metrics out
  through the gateway's Prometheus exporter on `:8889`, which the existing Prometheus scrapes by pod annotation (the
  app's job name arrives as `exported_job`). The Collectors' own `otelcol_*` metrics are scraped too (gateway `:8889`,
  agent `:8888`); watch `otelcol_exporter_send_failed_*` and `otelcol_exporter_queue_size` for dropped telemetry.
- `k8s_attributes` adds the pod's namespace, name, uid, node, owner (Deployment, StatefulSet...), container and image,
  plus the pod labels `app.kubernetes.io/name`, `app.kubernetes.io/instance`, `app.kubernetes.io/version` and `app`
  (as `k8s.pod.label.<key>`), on both Collectors.
- Processors, in order: `memory_limiter`, `k8s_attributes`, `resource_detection`, (gateway only) `attributes/redact`,
  `batch`. Redaction deletes any attribute whose name contains `authorization` or `cookie`, plus `url.query`/`url.full`.
- The agent lifts `trace_id`, `span_id` and `severity` out of JSON log lines, so logs link to traces. It skips pods in
  `otel`, `victoria-logs`, `victoria-traces` and `grafana` (the stack's own pods). It keeps read offsets in hostPath `/var/lib/otelcol` and runs as root
  (pod log files are root-only). Kubernetes (k3s defaults) rotates each container's log file on the node.
- `GOMEMLIMIT` is 80% of each Collector's memory limit; the memory limiter sits at 75%.

### Memory budget
What the stack can take from the node, by memory limit (requests in brackets):

| Component | Namespace | Limit (request) |
|---|---|---|
| `otel-gateway` | `otel` | 256Mi (128Mi) |
| `otel-agent` (one per node) | `otel` | 192Mi (96Mi) |
| VictoriaLogs | `victoria-logs` | 256Mi (128Mi) |
| VictoriaTraces | `victoria-traces` | 256Mi (128Mi) |
| **Collectors and stores, one node** | | **960Mi (480Mi)** |
| Grafana (was already running; now pinned) | `grafana` | 384Mi (128Mi) |

So the new parts add up to ~960Mi at their limits on a single-node cluster (each extra node adds another agent,
192Mi). Grafana is not new, but its limit is counted here because the stack now depends on it. The limits are caps, not typical
use.

### Install
Install the stores first (`../VictoriaLogsService`, `../VictoriaTracesService`), then:
```
./install-otel.sh
./verify-telemetry.sh --skip-grafana   # or without the flag once ../GrafanaService is installed
```
The old single `otel-collector` release (whose logs pipeline sent logs back into itself) is replaced by these two. If
it is installed, remove it first: `helm uninstall otel-collector --namespace otel`.

### Upgrade
Edit the values (or change the chart version in `chart-version`), then:
```
./upgrade-otel.sh
./verify-telemetry.sh
```

### Verify
`./verify-telemetry.sh` sends a log and a span with a fresh trace-id to the gateway from a short-lived curl pod (the
receivers bind the pod IP, so port-forwarding to the Collector doesn't work), waits until both are in the stores,
checks that the secret-bearing attributes it sent were redacted, and prints each store's disk usage against its caps.
First it prints the kubectl context it acts on and each node's container log rotation (the kubelet's
`containerLogMaxSize` and `containerLogMaxFiles`, read from `/api/v1/nodes/<node>/proxy/configz`).
It then checks Grafana through its API (port-forward, admin login from the `grafana-admin` Secret): both data sources
are healthy and linked to each other, the ID verification portal dashboard is provisioned, and the log it just sent is
found through Grafana by its reference code. Pass `--skip-grafana` before Grafana is installed. It exits non-zero on
any failure. Run it after every install or upgrade.

Every script here and in the store folders takes `--kube-context <ctx>` and honours `KUBECONFIG`, so they can be tried on
a throwaway cluster first, e.g. `kind create cluster --name obs --kubeconfig /tmp/kc` then `KUBECONFIG=/tmp/kc ./install-otel.sh`.

### Find a request by reference code
See `../GrafanaService/README.md` ("Finding a request by reference code"). In short: in Grafana's VictoriaLogs data
source search `trace_id:abcd1234*` (the code the portal showed) and follow the trace-id link to the trace.
