#!/bin/bash
helm repo update
helm upgrade cnpg cnpg/cloudnative-pg --namespace cnpg-system
kubectl apply -f cluster.yaml
