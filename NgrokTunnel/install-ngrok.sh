#!/bin/bash
# Required environment variables:
#   export NGROK_API_KEY=<your-api-key>
#   export NGROK_AUTHTOKEN=<your-authtoken>

source ../.env
helm repo add ngrok https://charts.ngrok.com
helm repo update
helm install ngrok-operator ngrok/ngrok-operator \
  --namespace ngrok-operator \
  --create-namespace \
  --values ngrok-values.yaml \
  --set credentials.apiKey=$NGROK_API_KEY \
  --set credentials.authtoken=$NGROK_AUTHTOKEN
