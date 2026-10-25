#!/bin/bash
# First install of the Cloudflare Tunnel connector. See README.md for the one-time steps before this
# (Cloudflare account, `cloudflared tunnel create`, DNS route).
# Required in ../.env:
#   CLOUDFLARE_TUNNEL_CREDENTIALS=<path to the <tunnel-id>.json that `cloudflared tunnel create` wrote>
# Pass --kube-context <ctx> to target another cluster; KUBECONFIG is honoured as usual. Safe to run again: it replaces the
# Secret with the file's current contents, then runs upgrade-cloudflared.sh, which restarts the pods if the Secret changed.
set -euo pipefail
cd "$(dirname "$0")"
KUBECTL=(kubectl); [[ "${1:-}" == --kube-context ]] && KUBECTL+=(--context "$2")
fail() { echo "FAIL: $*" >&2; exit 1; }

source ../.env
: "${CLOUDFLARE_TUNNEL_CREDENTIALS:?CLOUDFLARE_TUNNEL_CREDENTIALS is not set (expected in ../.env)}"
CREDENTIALS=${CLOUDFLARE_TUNNEL_CREDENTIALS/#\~/$HOME}
[[ -r "$CREDENTIALS" ]] || fail "cannot read $CREDENTIALS"
TUNNEL_ID=$(sed -n 's/.*"TunnelID"[[:space:]]*:[[:space:]]*"\([0-9a-f-]*\)".*/\1/p' "$CREDENTIALS")
[[ -n "$TUNNEL_ID" ]] || fail "$CREDENTIALS has no TunnelID; is it the file \`cloudflared tunnel create\` wrote?"

# The credentials reach kubectl only through files only you can read and a pipe, never on a command line.
umask 077
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
printf '%s' "$TUNNEL_ID" >"$WORK/tunnel-id"
"${KUBECTL[@]}" create namespace cloudflared --dry-run=client -o yaml | "${KUBECTL[@]}" apply -f -
"${KUBECTL[@]}" create secret generic cloudflared-tunnel --namespace cloudflared \
  --from-file=credentials.json="$CREDENTIALS" --from-file=tunnel-id="$WORK/tunnel-id" \
  --dry-run=client -o yaml | "${KUBECTL[@]}" apply -f -
echo "Secret cloudflared-tunnel holds tunnel $TUNNEL_ID"

./upgrade-cloudflared.sh "$@"
