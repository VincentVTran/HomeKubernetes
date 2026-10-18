### Documentation
https://grafana.com/docs/grafana/latest/ and the chart: https://github.com/grafana/helm-charts/tree/grafana-10.0.0/charts/grafana

### What runs here (namespace `grafana`)
Grafana from chart `grafana/grafana` 10.0.0 (pinned in `chart-version`), image 12.4.12. Trace-to-logs links into
VictoriaLogs need Grafana 12.2 or newer, and the chart's default image is 12.1.1, so `grafana-values.yaml` pins the tag.

- Home network only: the LoadBalancer IP `192.168.2.21` and the internal gateway route (`/grafana`). Nothing is on the
  external (ngrok) route; keep it that way.
- Data sources, all provisioned from `grafana-values.yaml`:

  | Name | uid | Reads | Links |
  |---|---|---|---|
  | Prometheus Server | (generated) | `http://prometheus-server.prometheus.svc.cluster.local:80/prometheus` | |
  | VictoriaLogs | `victorialogs` | `http://victoria-logs.victoria-logs.svc.cluster.local:9428` (official plugin `victoriametrics-logs-datasource` 0.32.0) | a log line's `trace_id` opens its trace |
  | VictoriaTraces | `victoriatraces` | `http://victoria-traces.victoria-traces.svc.cluster.local:10428/select/jaeger` (Jaeger type) | a span opens its log lines (`trace_id:="<id>"`) |

  The plugin is signed and is downloaded when the pod starts, so the pod needs internet access.
- Dashboards: the cluster dashboard (Grafana.com 315) and **ID verification portal** (`dashboards/id-verification-portal.json`,
  uid `id-verification-portal`):
  - request rate, error rate (share of 5xx) and p95 latency per route, from the app's
    `http_server_request_duration_seconds_*` metrics in Prometheus. The cluster's Prometheus job has no `honor_labels`, so
    the app's job arrives as `exported_job` (`id-verification-portal`, or `id-verification-portal/id-verification-portal`
    when the Collector adds the namespace); the queries match both;
  - **Recent errors**: the latest log lines with severity error or worse from the namespace in the dashboard's
    *Namespace (logs)* box (default `id-verification-portal`), with their reference code. Click the reference code or
    the trace-id to open the trace.

  The dashboard is read-only in Grafana. Edit the JSON file and run `./upgrade-grafana.sh`; the scripts pass it to the
  chart with `--set-file`.
- Resources: 128–384Mi memory, 50–500m CPU. Data (users, saved dashboards) is on a 2Gi PVC.

### Admin password
The admin login comes from the Secret `grafana-admin` (keys `admin-user`, `admin-password`). It is never in this
repository. Create it before the first install:
```
kubectl create namespace grafana
kubectl create secret generic grafana-admin --namespace grafana \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$(openssl rand -base64 24)"
```
Read it back with `kubectl get secret grafana-admin --namespace grafana -o jsonpath='{.data.admin-password}' | base64 -d`.

Grafana only uses the Secret when it creates its database. On an install that already has data on the PVC (or after
changing the Secret), set the stored password to match:
```
kubectl get secret grafana-admin --namespace grafana -o jsonpath='{.data.admin-password}' | base64 -d \
  | kubectl exec -i --namespace grafana deploy/grafana -c grafana -- grafana cli admin reset-admin-password --password-from-stdin
```

### Install
Install the stores and the Collectors first (`../VictoriaLogsService`, `../VictoriaTracesService`, `../OtelService`),
create the Secret above, then:
```
./install-grafana.sh
../OtelService/verify-telemetry.sh
```

### Upgrade
Edit `grafana-values.yaml` or `dashboards/*.json` (or change the chart version in `chart-version`), then:
```
./upgrade-grafana.sh
../OtelService/verify-telemetry.sh
```
The existing install was on 12.1.1 without a pinned chart version or an admin Secret: create the Secret, run
`./upgrade-grafana.sh`, then reset the stored password as above.

### Verify
`../OtelService/verify-telemetry.sh` sends a log and a span through the Collector, finds them in the stores, and then
checks Grafana through its API (port-forward, admin login from the Secret): both data sources are healthy and linked to
each other, the ID verification portal dashboard is provisioned, and the log it just sent is found through Grafana by
its reference code. Both scripts here and the verify script take `--kube-context <ctx>` and honour `KUBECONFIG`.

### Finding a request by reference code
When something fails, the Applicant Page and the Admin Page show **Reference: `<code>`**: the first 8 hex characters
of the request's trace-id.

1. Open Grafana, then **Explore** and pick the **VictoriaLogs** data source.
2. Search with the code followed by `*`, over a time range that covers the request (logs are kept 14 days):
   ```
   trace_id:abcd1234*
   ```
   Every log line written while handling that request appears. To see only errors, add `severity_number:>=17`.
3. Expand a line and click **View trace** next to `trace_id` to open the whole request in VictoriaTraces: the server
   span, database queries and Bouncr calls, each with its duration and status.
4. From any span, click its log icon (**Related logs**) to go back to the log lines of that trace.

With the full trace-id (from the `traceresponse` or `Server-Timing` response header) search `trace_id:="<32 hex>"`.
Recent errors are also listed, with their codes, at the bottom of the **ID verification portal** dashboard.
