#!/bin/bash
helm repo update
helm upgrade argocd argo/argo-cd --namespace argocd --values argocd-values.yaml
