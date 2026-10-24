#!/bin/bash
# Checks the public path Internet -> Cloudflare -> cloudflared -> Gloo's external gateway -> the portal, from outside, after
# an install, a cutover step or an upgrade:
#   1. the cloudflared Deployment has all its replicas ready, each holding connections to Cloudflare (its /ready);
#   2. https://<host>/api/health answers {"ok":true} over a valid certificate, through Cloudflare, and /admin serves the web app;
#   3. a hostname the tunnel doesn't know never reaches the portal;
#   4. the internal-only paths (/grafana, /prometheus, /logs) are not served on the public address;
#   5. with --ngrok-host, the ngrok address still answers too (while both tunnels run; see README.md);
#   6. the caller's address: which X-Forwarded-For chain reaches the portal, and so which TRUST_PROXY (chart `trustProxy`)
#      picks out the caller. Fails if the portal's current value picks someone else, or if a caller can choose the address
#      by sending their own X-Forwarded-For. For this it adds, for a few seconds,
#      a route on a random path of the external VirtualService to a `whoami` echo pod in a throwaway namespace (verify-tunnel-<random>), and removes
#      both when it exits (also on Ctrl-C). Skip with --skip-caller-address.
#
#   ./verify-tunnel.sh                                  # host from tunnel-config.yaml, current kubectl context
#   ./verify-tunnel.sh --host portal.example.com
#   ./verify-tunnel.sh --ngrok-host <name>.ngrok-free.dev
#   ./verify-tunnel.sh --kube-context <ctx> --skip-caller-address
set -euo pipefail
cd "$(dirname "$0")"

KUBECTL=(kubectl)
CONTEXT=""
HOST=""
NGROK_HOST=""
CHECK_CALLER=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --kube-context) KUBECTL+=(--context "$2"); CONTEXT=$2; shift 2 ;;
    --host) HOST=$2; shift 2 ;;
    --ngrok-host) NGROK_HOST=$2; shift 2 ;;
    --skip-caller-address) CHECK_CALLER=""; shift ;;
    *) echo "usage: verify-tunnel.sh [--host <hostname>] [--ngrok-host <hostname>] [--kube-context <ctx>] [--skip-caller-address]" >&2; exit 2 ;;
  esac
done
fail() { echo "FAIL: $*" >&2; exit 1; }

# Say which cluster this is about to touch before touching it.
CONTEXT=${CONTEXT:-$(kubectl config current-context 2>/dev/null || true)}
echo "kubectl context: ${CONTEXT:-<none>} (kubeconfig: ${KUBECONFIG:-~/.kube/config})"
HOST=${HOST:-$(sed -n 's/^[[:space:]]*-[[:space:]]*hostname:[[:space:]]*\([^[:space:]#]*\).*/\1/p' tunnel-config.yaml | head -1)}
[[ -n "$HOST" && "$HOST" != example.com && "$HOST" != *.example.com ]] || fail "no portal hostname: pass --host, or set it in tunnel-config.yaml"
echo "portal hostname: $HOST${NGROK_HOST:+, ngrok hostname: $NGROK_HOST}"
rand() { od -An -tx1 -N4 /dev/urandom | tr -d ' \n'; }

# --- 1. cloudflared -------------------------------------------------------------------------------------------------
"${KUBECTL[@]}" rollout status deployment/cloudflared --namespace cloudflared --timeout=180s >/dev/null \
  || fail "deployment/cloudflared in cloudflared is not ready after 3 minutes: kubectl logs -n cloudflared deploy/cloudflared"
WANT=$("${KUBECTL[@]}" get deployment cloudflared --namespace cloudflared -o 'jsonpath={.spec.replicas}')
PODS=$("${KUBECTL[@]}" get pods --namespace cloudflared -l app=cloudflared --field-selector=status.phase=Running \
  -o 'jsonpath={range .items[*]}{.metadata.name}{"\n"}{end}')
READY=0
for pod in $PODS; do
  # The API server's pod proxy reaches the metrics port, so this needs no port-forward.
  ready=$("${KUBECTL[@]}" get --raw "/api/v1/namespaces/cloudflared/pods/$pod:2000/proxy/ready" 2>/dev/null) || ready=""
  connections=$(sed -n 's/.*"readyConnections":\([0-9]*\).*/\1/p' <<<"$ready")
  [[ "${connections:-0}" -gt 0 ]] || fail "pod $pod has no connection to Cloudflare (/ready: ${ready:-no answer})"
  echo "pod $pod: connected to Cloudflare ($connections connections)"
  READY=$((READY + 1))
done
[[ "$READY" -gt 0 && "$READY" -ge "$WANT" ]] || fail "$READY of ${WANT:-?} cloudflared pods are connected to Cloudflare"

# --- 2.-5. the public address, from this machine ------------------------------------------------------------------------
# get <url> [curl args...]: sets BODY and CODE. CODE is 000 when the request failed (no DNS record, TLS error...).
# curl's own error (no DNS record, TLS error...) goes into BODY only when the request failed.
get() {
  local url=$1; shift
  local out err
  err=$(mktemp)
  if ! out=$(curl -sS --max-time 15 -w '\n%{http_code}' "$@" "$url" 2>"$err"); then
    BODY=$(<"$err"); CODE=000; rm -f "$err"; return 0
  fi
  rm -f "$err"
  CODE=${out##*$'\n'}
  BODY=${out%$'\n'*}
}
short() { tr -s '[:space:]' ' ' <<<"$1" | cut -c1-200; }  # a body, cut down for a FAIL line (error pages are long)

check_health() {  # check_health <host> <name>
  get "https://$1/api/health"
  [[ "$CODE" == 200 && "$BODY" == '{"ok":true}' ]] || fail "https://$1/api/health ($2) answered $CODE: $(short "$BODY")"
  echo "https://$1/api/health ($2): ok"
}
check_health "$HOST" "Cloudflare"

# Only Cloudflare's edge serves /cdn-cgi/trace, so this proves the request went through Cloudflare (not, say, a stale DNS
# answer pointing elsewhere).
get "https://$HOST/cdn-cgi/trace"
[[ "$CODE" == 200 && "$BODY" == *"h=$HOST"* ]] || fail "https://$HOST/cdn-cgi/trace answered $CODE: is $HOST proxied by Cloudflare (orange cloud)?"
echo "served by Cloudflare ($(grep '^colo=' <<<"$BODY"), $(grep '^tls=' <<<"$BODY"))"

get "https://$HOST/admin" -D -
if [[ "$CODE" != 200 ]] || ! grep -qi '^content-type: text/html' <<<"$BODY"; then fail "https://$HOST/admin answered $CODE, not the web app"; fi
echo "https://$HOST/admin serves the web app"

# A hostname in the zone with no rule in tunnel-config.yaml. Without a wildcard DNS record it doesn't resolve at all; with
# one, cloudflared's catch-all answers 404. Either way it must never reach the portal.
ZONE=${HOST#*.}
UNKNOWN="verify-tunnel-$(rand).$ZONE"
get "https://$UNKNOWN/api/health"
[[ "$BODY" != '{"ok":true}' ]] || fail "https://$UNKNOWN/api/health reached the portal: tunnel-config.yaml's catch-all must be http_status:404"
if [[ "$CODE" == 000 ]]; then
  echo "unknown hostname $UNKNOWN: does not resolve (no wildcard DNS record, so tunnel-config.yaml's catch-all isn't exercised)"
else
  echo "unknown hostname $UNKNOWN: $CODE, not the portal"
fi

# The internal gateway's services must not be on the public address. The portal answers these paths with its own pages.
for check in "/grafana/api/health|\"database\"|Grafana" "/prometheus/-/ready|Prometheus|Prometheus" \
             "/logs/select/vmui/|VictoriaLogs|VictoriaLogs" "/logs/select/logsql/query?query=*|_stream|VictoriaLogs"; do
  IFS='|' read -r path marker name <<<"$check"
  get "https://$HOST$path"
  [[ "$BODY" != *"$marker"* ]] || fail "https://$HOST$path serves $name: internal routes must stay off the external gateway"
done
echo "Grafana, Prometheus and VictoriaLogs are not on the public address"

[[ -z "$NGROK_HOST" ]] || check_health "$NGROK_HOST" "ngrok"

# --- 6. the caller's address ----------------------------------------------------------------------------------------
if [[ -z "$CHECK_CALLER" ]]; then
  echo "PASS: https://$HOST reaches the portal through Cloudflare (caller address not checked)."
  exit 0
fi

RUN=$(rand)   # each run its own namespace and path, so a run straight after another doesn't meet its leftovers
ECHO_NS=verify-tunnel-$RUN
ROUTE_PATH="/__verify-tunnel-$RUN"
VS=(virtualservice external-vs --namespace gloo-system)
cleanup() {
  local index
  index=$("${KUBECTL[@]}" get "${VS[@]}" -o 'jsonpath={range .spec.virtualHost.routes[*]}{.matchers[0].exact}{"\n"}{end}' 2>/dev/null \
    | grep -nxF "$ROUTE_PATH" | cut -d: -f1 | head -1) || true
  if [[ -n "$index" ]]; then
    # `test` first: only ever remove the route this run added, even if the list changed meanwhile.
    "${KUBECTL[@]}" patch "${VS[@]}" --type=json -p "[{\"op\":\"test\",\"path\":\"/spec/virtualHost/routes/$((index - 1))/matchers/0/exact\",\"value\":\"$ROUTE_PATH\"},{\"op\":\"remove\",\"path\":\"/spec/virtualHost/routes/$((index - 1))\"}]" >/dev/null \
      || echo "WARN: could not remove the route $ROUTE_PATH from external-vs; remove it by hand" >&2
  fi
  "${KUBECTL[@]}" delete namespace "$ECHO_NS" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM

echo "Measuring the caller's address (temporary route $ROUTE_PATH to a whoami pod in namespace $ECHO_NS)"
"${KUBECTL[@]}" create namespace "$ECHO_NS" >/dev/null
"${KUBECTL[@]}" run whoami --namespace "$ECHO_NS" --image=traefik/whoami:v1.12.0 --port=80 --expose >/dev/null
"${KUBECTL[@]}" wait pod/whoami --namespace "$ECHO_NS" --for=condition=Ready --timeout=120s >/dev/null \
  || fail "the whoami pod did not start"
"${KUBECTL[@]}" patch "${VS[@]}" --type=json -p "[{\"op\":\"add\",\"path\":\"/spec/virtualHost/routes/0\",\"value\":{\"matchers\":[{\"exact\":\"$ROUTE_PATH\"}],\"routeAction\":{\"single\":{\"kube\":{\"ref\":{\"name\":\"whoami\",\"namespace\":\"$ECHO_NS\"},\"port\":80}}}}}]" >/dev/null

# echo_headers <host> [curl args...]: what whoami saw, once Gloo has picked up the route (a few seconds).
echo_headers() {
  local host=$1 _; shift
  for _ in $(seq 1 15); do
    get "https://$host$ROUTE_PATH" "$@"
    [[ "$CODE" == 200 && "$BODY" == *"Hostname: whoami"* ]] && return 0
    sleep 2
  done
  fail "the temporary route on https://$host$ROUTE_PATH never answered (last: $CODE)"
}
header() { { grep -i "^$1:" <<<"$BODY" || true; } | head -1 | cut -d: -f2- | sed 's/^ *//; s/\r$//'; }

# trust_proxy_for <chain> <caller>: the TRUST_PROXY that picks <caller> out of <chain>, as the portal does
# (apps/server/src/http/sign-in-limits.ts: hops[hops.length - TRUST_PROXY]). Empty when the caller isn't in the chain.
trust_proxy_for() {
  awk -v chain="$1" -v caller="$2" 'BEGIN {
    n = split(chain, hops, ","); for (i = 1; i <= n; i++) gsub(/ /, "", hops[i])
    for (i = n; i >= 1; i--) if (hops[i] == caller) { print n - i + 1; exit }
  }'
}

echo_headers "$HOST"
CALLER=$(header Cf-Connecting-Ip)
CHAIN=$(header X-Forwarded-For)
[[ -n "$CALLER" ]] || fail "no CF-Connecting-IP header arrived: is $HOST proxied by Cloudflare?"
echo "caller (CF-Connecting-IP): $CALLER"
echo "X-Forwarded-For at the portal: ${CHAIN:-<none>}"
NEEDED=$(trust_proxy_for "$CHAIN" "$CALLER")
[[ -n "$NEEDED" ]] || fail "the caller $CALLER is not in X-Forwarded-For, so no TRUST_PROXY finds them"

# The portal chart's Deployment (label app.kubernetes.io/name=id-verification-portal), container `portal`.
CURRENT=$("${KUBECTL[@]}" get deployment --namespace id-verification-portal -l app.kubernetes.io/name=id-verification-portal -o \
  'jsonpath={.items[0].spec.template.spec.containers[?(@.name=="portal")].env[?(@.name=="TRUST_PROXY")].value}' 2>/dev/null) || CURRENT=""

if [[ -n "$NGROK_HOST" ]]; then
  echo_headers "$NGROK_HOST"
  NGROK_CHAIN=$(header X-Forwarded-For)
  echo "X-Forwarded-For through ngrok: ${NGROK_CHAIN:-<none>} (TRUST_PROXY that finds $CALLER: $(trust_proxy_for "$NGROK_CHAIN" "$CALLER" | grep . || echo 'none; ngrok may have used another address family'))"
fi

if [[ -z "$CURRENT" ]]; then
  echo "WARN: could not read the portal's TRUST_PROXY (namespace id-verification-portal); it must be $NEEDED behind Cloudflare" >&2
elif [[ "$CURRENT" != "$NEEDED" ]]; then
  fail "the portal runs with TRUST_PROXY=$CURRENT, which picks the wrong address behind Cloudflare; it must be $NEEDED (chart value trustProxy)"
else
  echo "the portal's TRUST_PROXY=$CURRENT picks out the caller"
fi

# A caller who sends their own X-Forwarded-For must not be able to choose the address their sign-ins count against.
FORGED=203.0.113.7
echo_headers "$HOST" -H "X-Forwarded-For: $FORGED"
FORGED_CHAIN=$(header X-Forwarded-For)
PICKED=$(awk -v chain="$FORGED_CHAIN" -v n="${CURRENT:-$NEEDED}" 'BEGIN { k = split(chain, hops, ","); gsub(/ /, "", hops[k - n + 1]); print hops[k - n + 1] }')
echo "with a forged X-Forwarded-For: $FORGED_CHAIN"
[[ "$PICKED" == "$CALLER" ]] || fail "a forged X-Forwarded-For: $FORGED makes TRUST_PROXY=${CURRENT:-$NEEDED} pick $PICKED instead of the caller $CALLER"
echo "a forged X-Forwarded-For doesn't change the address the portal picks"
echo "PASS: https://$HOST reaches the portal through Cloudflare, and sign-in limits see the caller's own address."
