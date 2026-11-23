#!/usr/bin/env bash
# EFK: Elasticsearch + Kibana (managed by the ECK operator) and Fluent Bit.
set -euo pipefail
cd "$(dirname "$0")/.."

helm repo add elastic https://helm.elastic.co >/dev/null 2>&1 || true
helm repo add fluent https://fluent.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update elastic fluent >/dev/null

echo ">> ECK operator"
helm upgrade --install elastic-operator elastic/eck-operator \
  --namespace elastic-system --create-namespace --wait --timeout 5m

echo ">> Elasticsearch + Kibana"
kubectl apply -k k8s/logging
# Wait for ECK to create the pod, then for the cluster to report green.
for _ in $(seq 1 60); do
  kubectl -n logging get pod logging-es-default-0 >/dev/null 2>&1 && break
  sleep 5
done
kubectl -n logging wait pod/logging-es-default-0 --for=condition=Ready --timeout=10m
kubectl -n logging wait elasticsearch/logging --for=jsonpath='{.status.health}'=green --timeout=5m

# Single-node cluster: no replicas, otherwise every index stays "yellow".
PW=$(kubectl -n logging get secret logging-es-elastic-user -o jsonpath='{.data.elastic}' | base64 -d)
kubectl -n logging exec logging-es-default-0 -c elasticsearch -- \
  curl -sk -u "elastic:${PW}" -X PUT "https://localhost:9200/_index_template/k8s-logs" \
  -H 'Content-Type: application/json' \
  -d '{"index_patterns":["k8s-logs-*"],"template":{"settings":{"number_of_replicas":0}}}' >/dev/null

echo ">> Fluent Bit"
SM=false
kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1 && SM=true
helm upgrade --install fluent-bit fluent/fluent-bit --namespace logging \
  -f helm/fluent-bit-values.yaml --set serviceMonitor.enabled="$SM" --wait --timeout 5m

kubectl -n logging wait kibana/logging --for=jsonpath='{.status.health}'=green --timeout=10m

echo
echo "Logging is up."
echo "  Kibana: kubectl -n logging port-forward svc/logging-kb-http 5601   -> https://localhost:5601"
echo "          user elastic, password: kubectl -n logging get secret logging-es-elastic-user -o jsonpath='{.data.elastic}' | base64 -d"
echo "          then create a data view for 'k8s-logs-*'"
