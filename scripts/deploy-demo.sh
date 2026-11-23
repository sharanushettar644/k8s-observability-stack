#!/usr/bin/env bash
# podinfo + traffic generator (+ ServiceMonitor when Prometheus Operator is installed).
set -euo pipefail
cd "$(dirname "$0")/.."
if kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
  kubectl apply -k k8s/demo-app
else
  kubectl apply -f k8s/demo-app/namespace.yaml
  kubectl -n demo apply -f k8s/demo-app/podinfo.yaml -f k8s/demo-app/traffic-generator.yaml
fi
kubectl -n demo rollout status deploy/podinfo --timeout=3m
kubectl -n demo rollout status deploy/traffic-generator --timeout=3m
