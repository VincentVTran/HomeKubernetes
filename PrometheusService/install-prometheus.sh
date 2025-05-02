#!/bin/bash
# Add the Prometheus Helm chart repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus using Helm with the custom values.yaml
helm install prometheus prometheus-community/prometheus \
    --namespace prometheus \
    --create-namespace \
    --values prometheus-values.yaml