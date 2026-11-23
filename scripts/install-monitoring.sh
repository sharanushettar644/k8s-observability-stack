#!/usr/bin/env bash
# Prometheus + Alertmanager + Grafana (kube-prometheus-stack), our alert rules
# and dashboards.
#   GRAFANA_PASSWORD   Grafana admin password (random if unset)
#   SLACK_WEBHOOK_URL  Slack incoming webhook for alerts (alerts are dropped if unset)
#   KPS_VERSION        chart version (latest if unset)
set -euo pipefail
cd "$(dirname "$0")/.."

NS=monitoring
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

if ! kubectl -n "$NS" get secret grafana-admin >/dev/null 2>&1; then
  PASSWORD=${GRAFANA_PASSWORD:-$(openssl rand -hex 12)}
  kubectl -n "$NS" create secret generic grafana-admin \
    --from-literal=admin-user=admin --from-literal=admin-password="$PASSWORD"
fi

# Placeholder URL keeps Alertmanager valid when no Slack webhook is configured.
kubectl -n "$NS" create secret generic alertmanager-slack \
  --from-literal=webhook-url="${SLACK_WEBHOOK_URL:-http://localhost:9/slack-not-configured}" \
  --dry-run=client -o yaml | kubectl apply -f -

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update prometheus-community >/dev/null
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  --namespace "$NS" ${KPS_VERSION:+--version "$KPS_VERSION"} \
  -f helm/kube-prometheus-stack-values.yaml --wait --timeout 10m

kubectl apply -k k8s/monitoring

echo
echo "Monitoring is up."
echo "  Grafana     : kubectl -n $NS port-forward svc/kps-grafana 3000:80        -> http://localhost:3000"
echo "                user admin, password: kubectl -n $NS get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d"
echo "  Prometheus  : kubectl -n $NS port-forward svc/kps-prometheus 9090        -> http://localhost:9090"
echo "  Alertmanager: kubectl -n $NS port-forward svc/kps-alertmanager 9093      -> http://localhost:9093"
