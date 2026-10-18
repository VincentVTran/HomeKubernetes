### Documentation
https://docs.victoriametrics.com/victorialogs/ and the chart: https://github.com/VictoriaMetrics/helm-charts/tree/master/charts/victoria-logs-single

### What runs here (namespace `victoria-logs`)
VictoriaLogs, single node, from chart `vm/victoria-logs-single` (version pinned in the scripts), as StatefulSet and headless
Service `victoria-logs` on port 9428.
- Written by: Logs from the gateway Collector over OTLP/HTTP: `http://victoria-logs.victoria-logs.svc.cluster.local:9428/insert/opentelemetry/v1/logs`.
- Read by: Grafana (VictoriaLogs plugin) and LogsQL: `http://victoria-logs.victoria-logs.svc.cluster.local:9428` (`/select/logsql/query`).
- No external access (no ingress, no LoadBalancer). Use `kubectl port-forward` for the web UI.
- Resources: 128–256Mi memory, 50–500m CPU. Metrics (`vl_*`) are scraped by the existing Prometheus.

### Retention
Capped by days **and** by disk size; when either is reached, the oldest day is deleted:

| Days | Disk size cap | Volume |
|---|---|---|
| 14d | 20 GiB | 25Gi |

The disk size cap (`retentionDiskSpaceUsage`) is the real limit, because `local-path` volumes don't enforce their size.
The last two days are always kept, even past the cap, so the volume has headroom. `../OtelService/verify-telemetry.sh`
prints usage against the caps; tune them in `victoria-logs-values.yaml`. A `retentionPeriod` without a unit means
months, so keep the `d`.

### Install
```
./install-victoria-logs.sh
```

### Upgrade
```
./upgrade-victoria-logs.sh
```
Then run `../OtelService/verify-telemetry.sh`. Both scripts take `--kube-context <ctx>` and honour `KUBECONFIG`.

### Look inside
```
kubectl port-forward --namespace victoria-logs svc/victoria-logs 9428
```
Web UI: http://localhost:9428/select/vmui. API:
```
curl -s localhost:9428/select/logsql/query --data-urlencode 'query=trace_id:abcd1234*'   # by reference code
```
