#!/bin/bash
source .env

helm repo update
helm upgrade ngrok-operator ngrok/ngrok-operator \
  --namespace ngrok-operator \
  --values ngrok-values.yaml \
  --set credentials.apiKey=$NGROK_API_KEY \
  --set credentials.authtoken=$NGROK_AUTHTOKEN
