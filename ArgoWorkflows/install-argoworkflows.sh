#!/bin/bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Argo Workflows
helm install argo-workflows argo/argo-workflows --namespace argo --create-namespace --values argoworkflows-values.yaml

# Argo Events (installs the operator that processes EventBus, EventSource, and Sensor CRDs)
helm install argo-events argo/argo-events --namespace argo --create-namespace --values argoevents-values.yaml
