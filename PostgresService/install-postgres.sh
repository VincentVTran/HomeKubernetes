#!/bin/bash
# Shared Postgres for apps in the cluster: the CloudNativePG operator, then one Cluster in the `postgres` namespace.
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update

helm install cnpg cnpg/cloudnative-pg \
    --namespace cnpg-system \
    --create-namespace

# Wait for the operator before creating the Cluster it manages.
kubectl rollout status deployment/cnpg-cloudnative-pg --namespace cnpg-system --timeout=180s
kubectl apply -f cluster.yaml
