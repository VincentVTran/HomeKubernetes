#!/bin/bash
# Being retired: the Cloudflare Tunnel replaces ngrok. See ../CloudflareTunnel/README.md (phase 7 removes this folder).
# Required in ../.env:
#   NGROK_API_KEY=<your-api-key>
#   NGROK_AUTHTOKEN=<your-authtoken>
set -euo pipefail
cd "$(dirname "$0")"

# Keep in step with upgrade-ngrok.sh
CHART_VERSION=0.24.1

source ../.env
: "${NGROK_API_KEY:?NGROK_API_KEY is not set (expected in ../.env)}"
: "${NGROK_AUTHTOKEN:?NGROK_AUTHTOKEN is not set (expected in ../.env)}"

helm repo add ngrok https://charts.ngrok.com
helm repo update ngrok
helm install ngrok-operator ngrok/ngrok-operator \
  --namespace ngrok-operator \
  --create-namespace \
  --version "$CHART_VERSION" \
  --values ngrok-values.yaml \
  --set credentials.apiKey="$NGROK_API_KEY" \
  --set credentials.authtoken="$NGROK_AUTHTOKEN"
