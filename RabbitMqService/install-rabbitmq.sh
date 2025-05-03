#!/bin/bash
# Add the Prometheus Helm chart repository
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Install Prometheus using Helm with the custom values.yaml
helm install rabbitmq bitnami/rabbitmq \
    --namespace rabbitmq \
    --create-namespace \
    --values rabbitmq-values.yaml