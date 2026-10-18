### Documentation
https://docs.victoriametrics.com/victoriatraces/ and the chart: https://github.com/VictoriaMetrics/helm-charts/tree/master/charts/victoria-traces-single

### What runs here (namespace `victoria-traces`)
VictoriaTraces, single node, from chart `vm/victoria-traces-single` (version pinned in `chart-version`, read by both scripts), as StatefulSet and headless
Service `victoria-traces` on port 10428.
- Written by: Traces from the gateway Collector over OTLP/HTTP: `http://victoria-traces.victoria-traces.svc.cluster.local:10428/insert/opentelemetry/v1/traces`.
- Read by: Grafana (Jaeger data source): `http://victoria-traces.victoria-traces.svc.cluster.local:10428/select/jaeger`.
- No external access (no ingress, no LoadBalancer). Use `kubectl port-forward` for the web UI.
- Resources: 128–256Mi memory, 50–500m CPU. Metrics (`vt_*`) are scraped by the existing Prometheus.

### Retention
Capped by days **and** by disk size; when either is reached, the oldest day is deleted:

| Days | Disk size cap | Volume |
|---|---|---|
| 7d | 10 GiB | 15Gi |

The disk size cap (`retentionDiskSpaceUsage`) is the real limit, because `local-path` volumes don't enforce their size.
The last two days are always kept, even past the cap, so the volume has headroom. `../OtelService/verify-telemetry.sh`
prints usage against the caps; tune them in `victoria-traces-values.yaml`. A `retentionPeriod` without a unit means
months, so keep the `d`.

### Install
```
./install-victoria-traces.sh
```

### Upgrade
```
./upgrade-victoria-traces.sh
```
Then run `../OtelService/verify-telemetry.sh`. Both scripts take `--kube-context <ctx>` and honour `KUBECONFIG`.

### Look inside
```
kubectl port-forward --namespace victoria-traces svc/victoria-traces 10428
```
Web UI: http://localhost:10428/select/vmui. API:
```
curl -s localhost:10428/select/jaeger/api/traces/<32-hex trace-id>
```
