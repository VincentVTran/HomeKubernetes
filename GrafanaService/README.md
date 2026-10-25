### Documentation
https://grafana.com/docs/grafana/latest/ and the chart: https://github.com/grafana/helm-charts/tree/grafana-10.0.0/charts/grafana

### What runs here (namespace `grafana`)
Grafana from chart `grafana/grafana` 10.0.0 (pinned in `chart-version`), image 12.4.12. Trace-to-logs links into
VictoriaLogs need Grafana 12.2 or newer, and the chart's default image is 12.1.1, so `grafana-values.yaml` pins the tag.

- Home network only: the LoadBalancer IP `192.168.2.21` and the internal gateway route (`/grafana`). Nothing is on the
  external (public tunnel) route; keep it that way.
- Data sources, all provisioned from `grafana-values.yaml`:

  | Name | uid | Reads | Links |
  |---|---|---|---|
  | Prometheus Server | (generated) | `http://prometheus-server.prometheus.svc.cluster.local:80/prometheus` | |
  | VictoriaLogs | `victorialogs` | `http://victoria-logs.victoria-logs.svc.cluster.local:9428` (official plugin `victoriametrics-logs-datasource` 0.32.0) | a log line's `trace_id` opens its trace |
  | VictoriaTraces | `victoriatraces` | `http://victoria-traces.victoria-traces.svc.cluster.local:10428/select/jaeger` (Jaeger type) | a span opens its log lines (`trace_id:="<id>"`) |

  The plugin is signed and is downloaded when the pod starts, so the pod needs internet access.
- Removing or renaming a dashboard: delete or rename its file in `dashboards/` and the matching `--set-file` line in both
  scripts, then run `./upgrade-grafana.sh`. Grafana then removes the old one (the `portal` provider has `disableDeletion: false`).
  If it stays, an empty file of its old name is left on Grafana's volume, where the old file was mounted: Grafana still finds the
  file, so it doesn't remove the dashboard. Delete that file (only if it is empty):
  `kubectl -n grafana exec deploy/grafana -c grafana -- sh -c 'f=/var/lib/grafana/dashboards/portal/<old>.json; [ ! -s "$f" ] && rm "$f"'`.
  This happened when the portal's dashboard was renamed to `applicant-portal`.
- Dashboards: the cluster dashboard (Grafana.com 315) and **Applicant Portal** (`dashboards/applicant-portal.json`,
  uid `applicant-portal`):
  - request rate, error rate (share of 5xx) and p95 latency per route, from the app's
    `http_server_request_duration_seconds_*` metrics in Prometheus. The cluster's Prometheus job has no `honor_labels`, so
    the app's job arrives as `exported_job` (`applicant-portal`, or `applicant-portal/applicant-portal`
    when the Collector adds the namespace); the queries match both;
  - **Recent errors**: the latest log lines with severity error or worse from the namespace in the dashboard's
    *Namespace (logs)* box (default `applicant-portal`), with their reference code. Click the reference code or
    the trace-id to open the trace.
  - **Recent logs**: the latest 200 lines from the same namespace at every level except debug, with a colour-coded
    level (info, warn, error, and Unspecified for anything written outside the server's logger, such as Node's warnings
    or a crash's stack trace). The portal writes one line per request (`GET /api/applicants 200`), so this shows what
    it has been doing. The Level column is filterable; the reference code opens the trace.

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
each other, the Applicant Portal dashboard is provisioned, and the log it just sent is found through Grafana by
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
Recent errors are also listed, with their codes, at the bottom of the **Applicant Portal** dashboard.
