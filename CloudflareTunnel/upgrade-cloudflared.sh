#!/bin/bash
# Applies tunnel-config.yaml and cloudflared.yaml (a new image tag, a new hostname...) to the cluster and waits for the pods.
# The `cloudflared-tunnel` Secret must already exist (install-cloudflared.sh makes it).
# Pass --kube-context <ctx> to target another cluster; KUBECONFIG is honoured as usual.
set -euo pipefail
cd "$(dirname "$0")"
KUBECTL=(kubectl); [[ "${1:-}" == --kube-context ]] && KUBECTL+=(--context "$2")
fail() { echo "FAIL: $*" >&2; exit 1; }

# Every public hostname must be a real one, and must also be in an external VirtualService, or Gloo answers 404 for it.
HOSTNAMES=$(sed -n 's/^[[:space:]]*-[[:space:]]*hostname:[[:space:]]*\([^[:space:]#]*\).*/\1/p' tunnel-config.yaml)
[[ -n "$HOSTNAMES" ]] || fail "tunnel-config.yaml has no hostname rules"
for host in $HOSTNAMES; do
  [[ "$host" != example.com && "$host" != *.example.com ]] || fail "tunnel-config.yaml still has the placeholder $host: put your portal hostname there"
  grep -qE "^[[:space:]]*-[[:space:]]*['\"]?${host//./\\.}['\"]?[[:space:]]*(#.*)?$" ../GlooGateway/routes/external-routes.yaml \
    || fail "$host is not in the domains of ../GlooGateway/routes/external-routes.yaml; add it there and apply the routes first"
done
"${KUBECTL[@]}" get secret cloudflared-tunnel --namespace cloudflared >/dev/null 2>&1 \
  || fail "no Secret cloudflared-tunnel in namespace cloudflared: run ./install-cloudflared.sh first"

# Over the config and the Secret, so new credentials (install-cloudflared.sh run again) also restart the pods: they read the
# tunnel id only when they start.
CHECKSUM=$({ cat tunnel-config.yaml; "${KUBECTL[@]}" get secret cloudflared-tunnel --namespace cloudflared -o 'jsonpath={.data}'; } \
  | sha256sum | cut -c1-16)
"${KUBECTL[@]}" create configmap cloudflared-config --namespace cloudflared \
  --from-file=config.yaml=tunnel-config.yaml --dry-run=client -o yaml | "${KUBECTL[@]}" apply -f -
sed "s/__CONFIG_CHECKSUM__/$CHECKSUM/" cloudflared.yaml | "${KUBECTL[@]}" apply -f -
"${KUBECTL[@]}" rollout status deployment/cloudflared --namespace cloudflared --timeout=180s \
  || fail "cloudflared is not ready after 3 minutes: kubectl logs -n cloudflared deploy/cloudflared"
echo "cloudflared is up for: $HOSTNAMES"
