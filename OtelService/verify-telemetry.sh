#!/bin/bash
# Checks the whole logs-and-traces path after an install or upgrade:
#   1. sends one log record and one span, sharing a fresh trace-id, to the gateway Collector over OTLP/HTTP;
#   2. waits until the log is in VictoriaLogs and the span is in VictoriaTraces (fails after a timeout);
#   3. checks the gateway's redaction removed the secret-bearing attributes that were sent on purpose;
#   4. prints each store's disk usage against its caps.
# Everything runs from a short-lived curl pod in the `otel` namespace, because the Collector's receivers bind the
# pod IP (so `kubectl port-forward` to the Collector does not work).
#
#   ./verify-telemetry.sh                        # current kubectl context
#   ./verify-telemetry.sh --kube-context <ctx>   # another context; KUBECONFIG is honoured as usual
set -euo pipefail

KUBECTL=(kubectl)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --kube-context) KUBECTL+=(--context "$2"); shift 2 ;;
    *) echo "usage: verify-telemetry.sh [--kube-context <ctx>]" >&2; exit 2 ;;
  esac
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
      printf "%-15s used %.1f MiB of %s cap (retention %s), %.1f GiB free on the volume\n", name, used/1048576, cap, days, free/1073741824
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
if grep -q '^RESULT: ok' <<<"$OUTPUT"; then
  echo "PASS: logs and traces reach their stores. Find this run with trace_id:=\"$TRACE_ID\" (reference code ${TRACE_ID:0:8})."
else
  echo "FAIL: see above." >&2
  exit 1
fi
