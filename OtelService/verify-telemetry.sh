#!/bin/bash
# Checks the whole logs-and-traces path after an install or upgrade:
#   1. sends one log record and one span, sharing a fresh trace-id, to the gateway Collector over OTLP/HTTP;
#   2. waits until the log is in VictoriaLogs and the span is in VictoriaTraces (fails after a timeout);
#   3. checks the gateway's redaction removed the secret-bearing attributes that were sent on purpose;
#   4. prints each store's disk usage against its caps;
#   (first of all it prints the kubectl context it acts on, and each node's container log rotation from the kubelet's
#   configz: containerLogMaxSize and containerLogMaxFiles, which bound the pod log files the agent reads);
#   5. checks Grafana through its API (port-forward, admin login from the `grafana-admin` Secret): both data sources
#      are healthy and linked to each other, the "ID verification portal" dashboard is provisioned, and the log just
#      sent is found through Grafana by its reference code (`trace_id:<first 8 hex>*`). Skip with --skip-grafana.
# Everything runs from a short-lived curl pod in the `otel` namespace, because the Collector's receivers bind the
# pod IP (so `kubectl port-forward` to the Collector does not work).
#
#   ./verify-telemetry.sh                        # current kubectl context
#   ./verify-telemetry.sh --kube-context <ctx>   # another context; KUBECONFIG is honoured as usual
#   ./verify-telemetry.sh --skip-grafana         # only the Collectors and the stores (Grafana not installed yet)
set -euo pipefail

KUBECTL=(kubectl)
CHECK_GRAFANA=1
CONTEXT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --kube-context) KUBECTL+=(--context "$2"); CONTEXT=$2; shift 2 ;;
    --skip-grafana) CHECK_GRAFANA=""; shift ;;
    *) echo "usage: verify-telemetry.sh [--kube-context <ctx>] [--skip-grafana]" >&2; exit 2 ;;
  esac
done

# Say which cluster this is about to touch before touching it.
CONTEXT=${CONTEXT:-$(kubectl config current-context 2>/dev/null || true)}
echo "kubectl context: ${CONTEXT:-<none>} (kubeconfig: ${KUBECONFIG:-~/.kube/config})"

# Container log rotation on each node: the kubelet rotates pod log files at containerLogMaxSize and keeps
# containerLogMaxFiles of them, which is what keeps the files the agent tails from filling the node's disk.
NODES=$("${KUBECTL[@]}" get nodes -o 'jsonpath={.items[*].metadata.name}') || { echo "FAIL: could not list nodes" >&2; exit 1; }
for node in $NODES; do
  configz=$("${KUBECTL[@]}" get --raw "/api/v1/nodes/$node/proxy/configz" 2>/dev/null) \
    || { echo "FAIL: could not read the kubelet configz of node $node" >&2; exit 1; }
  max_size=$(grep -o '"containerLogMaxSize":"[^"]*"' <<<"$configz" | cut -d'"' -f4)
  max_files=$(grep -o '"containerLogMaxFiles":[0-9]*' <<<"$configz" | cut -d: -f2)
  [[ -n "$max_size" && -n "$max_files" ]] \
    || { echo "FAIL: node $node's kubelet configz has no containerLogMaxSize/containerLogMaxFiles" >&2; exit 1; }
  echo "node $node: container logs rotate at $max_size, $max_files files kept"
done

TIMEOUT_SECONDS=${TIMEOUT_SECONDS:-90}
GATEWAY=http://otel-gateway.otel.svc.cluster.local:4318
LOGS=http://victoria-logs.victoria-logs.svc.cluster.local:9428
TRACES=http://victoria-traces.victoria-traces.svc.cluster.local:10428

TRACE_ID=$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')
SPAN_ID=$(od -An -tx1 -N8 /dev/urandom | tr -d ' \n')
NOW_NS="$(date +%s)000000000"
END_NS="$(( $(date +%s) + 1 ))000000000"
RESOURCE='{"attributes":[{"key":"service.name","value":{"stringValue":"verify-telemetry"}}]}'

# OTLP/JSON: ids are hex, times are nanoseconds as strings. The `cookie` and `authorization` attributes must be
# deleted by the gateway's redaction before they reach the stores.
LOG_JSON='{"resourceLogs":[{"resource":'$RESOURCE',"scopeLogs":[{"scope":{"name":"verify-telemetry"},"logRecords":[{"timeUnixNano":"'$NOW_NS'","severityNumber":9,"severityText":"INFO","body":{"stringValue":"verify-telemetry log '$TRACE_ID'"},"traceId":"'$TRACE_ID'","spanId":"'$SPAN_ID'","attributes":[{"key":"cookie","value":{"stringValue":"verify-secret"}}]}]}]}]}'
SPAN_JSON='{"resourceSpans":[{"resource":'$RESOURCE',"scopeSpans":[{"scope":{"name":"verify-telemetry"},"spans":[{"traceId":"'$TRACE_ID'","spanId":"'$SPAN_ID'","name":"verify-telemetry span","kind":2,"startTimeUnixNano":"'$NOW_NS'","endTimeUnixNano":"'$END_NS'","attributes":[{"key":"http.request.header.authorization","value":{"stringValue":"Bearer verify-secret"}}]}]}]}]}'

# Runs inside the pod (busybox sh + curl).
POD_SCRIPT=$(cat <<'SH'
set -u
fail() { echo "FAIL: $*"; exit 1; }

for signal in logs traces; do
  [ "$signal" = logs ] && body=$LOG_JSON || body=$SPAN_JSON
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -H 'Content-Type: application/json' \
    --data "$body" "$GATEWAY/v1/$signal") || code=000
  [ "$code" = 200 ] || fail "gateway answered $code to /v1/$signal"
  echo "sent $signal to the gateway"
done

log=""; trace=""; waited=0
while [ "$waited" -lt "$TIMEOUT_SECONDS" ]; do
  [ -z "$log" ] && log=$(curl -s --max-time 5 "$LOGS/select/logsql/query" \
    --data-urlencode "query=trace_id:=\"$TRACE_ID\"" | grep "$TRACE_ID")
  [ -z "$trace" ] && trace=$(curl -s --max-time 5 "$TRACES/select/jaeger/api/traces/$TRACE_ID" | grep "\"$SPAN_ID\"")
  [ -n "$log" ] && [ -n "$trace" ] && break
  sleep 2; waited=$((waited + 2))
done
[ -n "$log" ] || fail "log with trace_id $TRACE_ID not found in VictoriaLogs after ${TIMEOUT_SECONDS}s"
[ -n "$trace" ] || fail "span $SPAN_ID of trace $TRACE_ID not found in VictoriaTraces after ${TIMEOUT_SECONDS}s"
echo "found the log in VictoriaLogs and the span in VictoriaTraces after ~${waited}s"
echo "$log" | grep -q verify-secret && fail "the log's cookie attribute was not redacted: $log"
echo "$trace" | grep -q verify-secret && fail "the span's authorization attribute was not redacted"
echo "secret-bearing attributes were redacted"

# Disk usage against the caps the stores are running with (from their own `flag` metrics).
usage() {  # usage <name> <url> <metric prefix>
  curl -s --max-time 5 "$2/metrics" | awk -v name="$1" -v p="$3" '
    $1 ~ "^"p"_data_size_bytes" { used += $2 }
    $1 ~ "^"p"_free_disk_space_bytes" { free = $2 }
    /^flag\{/ && /name="retentionPeriod"/ { match($0, /value="[^"]*"/); days = substr($0, RSTART+7, RLENGTH-8) }
    /^flag\{/ && /name="retention.maxDiskSpaceUsageBytes"/ { match($0, /value="[^"]*"/); cap = substr($0, RSTART+7, RLENGTH-8) }
    END {
      if (used == "") { print "FAIL: no disk metrics from " name; exit 1 }
      printf "%-15s used %.2f MiB of %s cap (retention %s), %.1f GiB free on the volume\n", name, used/1048576, cap, days, free/1073741824
    }' || exit 1
}
usage VictoriaLogs "$LOGS" vl || fail "could not read VictoriaLogs metrics"
usage VictoriaTraces "$TRACES" vt || fail "could not read VictoriaTraces metrics"
echo "RESULT: ok"
SH
)

echo "Verifying logs and traces with trace-id $TRACE_ID"
OUTPUT=$("${KUBECTL[@]}" run "verify-telemetry-$(od -An -tx1 -N3 /dev/urandom | tr -d ' \n')" \
  --namespace otel --rm -i --quiet --restart=Never --image=curlimages/curl:8.10.1 \
  --env "LOG_JSON=$LOG_JSON" --env "SPAN_JSON=$SPAN_JSON" --env "TRACE_ID=$TRACE_ID" --env "SPAN_ID=$SPAN_ID" \
  --env "GATEWAY=$GATEWAY" --env "LOGS=$LOGS" --env "TRACES=$TRACES" --env "TIMEOUT_SECONDS=$TIMEOUT_SECONDS" \
  --command -- sh -c "$POD_SCRIPT" 2>&1) || true
echo "$OUTPUT"
if ! grep -q '^RESULT: ok' <<<"$OUTPUT"; then
  echo "FAIL: see above." >&2
  exit 1
fi
echo "PASS: logs and traces reach their stores. Find this run with trace_id:=\"$TRACE_ID\" (reference code ${TRACE_ID:0:8})."
[[ -n "$CHECK_GRAFANA" ]] || exit 0

# --- Grafana -------------------------------------------------------------------------------------------------------
# Grafana binds 0.0.0.0, so a port-forward works. The admin login comes from the Secret and is handed to curl on stdin,
# so it never appears in a process list.
echo "Checking Grafana"
gfail() { echo "FAIL: $*" >&2; exit 1; }
GRAFANA_NS=grafana
GRAFANA_PATH=/grafana   # grafana.ini server.root_url (serve_from_sub_path)
secret() { "${KUBECTL[@]}" get secret grafana-admin --namespace "$GRAFANA_NS" -o "jsonpath={.data.$1}" | base64 -d; }
GF_USER=$(secret admin-user 2>/dev/null) && GF_PASSWORD=$(secret admin-password 2>/dev/null) && [[ -n "$GF_PASSWORD" ]] \
  || gfail "no Secret grafana-admin (keys admin-user, admin-password) in namespace $GRAFANA_NS; see GrafanaService/README.md"

PF_LOG=$(mktemp)
"${KUBECTL[@]}" port-forward --namespace "$GRAFANA_NS" svc/grafana :80 >"$PF_LOG" 2>&1 &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null; rm -f "$PF_LOG"' EXIT
for _ in $(seq 1 30); do
  PORT=$(sed -n 's/^Forwarding from 127.0.0.1:\([0-9]*\).*/\1/p' "$PF_LOG" | head -1)
  [[ -n "$PORT" ]] && break
  kill -0 $PF_PID 2>/dev/null || gfail "port-forward to svc/grafana failed: $(cat "$PF_LOG")"
  sleep 1
done
[[ -n "${PORT:-}" ]] || gfail "port-forward to svc/grafana did not start"
GRAFANA="http://127.0.0.1:$PORT$GRAFANA_PATH"
gf() {  # gf <path> [curl args...]: prints the body, fails unless HTTP 200
  local path=$1; shift
  local out code
  out=$(printf 'user = "%s:%s"\n' "$GF_USER" "$GF_PASSWORD" | curl -s --config - --max-time 20 -w '\n%{http_code}' "$@" "$GRAFANA$path") \
    || gfail "could not reach Grafana at $path"
  code=${out##*$'\n'}
  [[ "$code" == 200 ]] || gfail "Grafana answered $code to $path: ${out%$'\n'*}"
  printf '%s' "${out%$'\n'*}"
}

for uid in victorialogs victoriatraces; do
  health=$(gf "/api/datasources/uid/$uid/health")
  grep -q '"status":"OK"' <<<"$health" || gfail "data source $uid is not healthy: $health"
  echo "data source $uid is healthy"
done
logs_ds=$(gf /api/datasources/uid/victorialogs)
traces_ds=$(gf /api/datasources/uid/victoriatraces)
grep -q '"datasourceUid":"victoriatraces"' <<<"$logs_ds" \
  || gfail "VictoriaLogs data source has no trace_id link to VictoriaTraces"
grep -q '"tracesToLogsV2":{[^}]*"datasourceUid":"victorialogs"' <<<"$traces_ds" \
  || gfail "VictoriaTraces data source has no trace-to-logs link to VictoriaLogs"
echo "log-to-trace and trace-to-logs links are set"

dashboard=$(gf /api/dashboards/uid/id-verification-portal)
grep -q '"title":"ID verification portal"' <<<"$dashboard" || gfail "dashboard id-verification-portal has the wrong title"
echo "dashboard \"ID verification portal\" is provisioned"

# The README's recipe: search VictoriaLogs through Grafana by reference code.
REFERENCE=${TRACE_ID:0:8}
QUERY='{"from":"now-1h","to":"now","queries":[{"refId":"A","datasource":{"uid":"victorialogs"},"expr":"trace_id:'$REFERENCE'*","queryType":"instant","maxLines":10}]}'
found=$(gf /api/ds/query -H 'Content-Type: application/json' --data "$QUERY")
grep -q "$TRACE_ID" <<<"$found" || gfail "reference code $REFERENCE not found through Grafana: $found"
echo "found the log through Grafana by reference code $REFERENCE"
echo "PASS: Grafana's data sources, links and dashboard are in place."
