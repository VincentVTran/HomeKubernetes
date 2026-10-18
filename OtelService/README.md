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
- Processors, in order: `memory_limiter`, `k8s_attributes`, `resource_detection`, (gateway only) `attributes/redact`,
  `batch`. Redaction deletes any attribute whose name contains `authorization` or `cookie`, plus `url.query`/`url.full`.
- The agent lifts `trace_id`, `span_id` and `severity` out of JSON log lines, so logs link to traces. It skips pods in
  `otel`, `victoria-logs` and `victoria-traces`. It keeps read offsets in hostPath `/var/lib/otelcol` and runs as root
  (pod log files are root-only). Kubernetes (k3s defaults) rotates each container's log file on the node.
- Resources: gateway 128–256Mi, agent 96–192Mi. `GOMEMLIMIT` is 80% of the limit; the memory limiter sits at 75%.

### Install
Install the stores first (`../VictoriaLogsService`, `../VictoriaTracesService`), then:
```
./install-otel.sh
./verify-telemetry.sh
```
The old single `otel-collector` release (whose logs pipeline sent logs back into itself) is replaced by these two. If
it is installed, remove it first: `helm uninstall otel-collector --namespace otel`.

### Upgrade
Edit the values (or bump `VERSION` in both scripts), then:
```
./upgrade-otel.sh
./verify-telemetry.sh
```

### Verify
`./verify-telemetry.sh` sends a log and a span with a fresh trace-id to the gateway from a short-lived curl pod (the
receivers bind the pod IP, so port-forwarding to the Collector doesn't work), waits until both are in the stores,
checks that the secret-bearing attributes it sent were redacted, and prints each store's disk usage against its caps.
It exits non-zero on any failure. Run it after every install or upgrade.

Every script here and in the store folders takes `--kube-context <ctx>` and honours `KUBECONFIG`, so they can be tried on
a throwaway cluster first, e.g. `kind create cluster --name obs --kubeconfig /tmp/kc` then `KUBECONFIG=/tmp/kc ./install-otel.sh`.

### Find a request by reference code
The portal shows a reference code: the first 8 hex characters of the request's trace-id. In Grafana's VictoriaLogs
data source (or the VictoriaLogs UI, see `../VictoriaLogsService`) search
```
trace_id:abcd1234*
```
and follow the trace-id link to the trace. With the full trace-id: `trace_id:="<32 hex>"`.
