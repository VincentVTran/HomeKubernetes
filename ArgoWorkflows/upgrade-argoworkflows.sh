#!/bin/bash
helm repo update

# Argo Workflows
helm upgrade argo-workflows argo/argo-workflows --namespace argo --values argoworkflows-values.yaml

# Argo Events
helm upgrade argo-events argo/argo-events --namespace argo --values argoevents-values.yaml
