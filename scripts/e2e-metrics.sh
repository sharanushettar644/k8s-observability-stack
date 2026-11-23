#!/usr/bin/env bash
# End-to-end check of the metrics pipeline on a live cluster:
#   1. Prometheus scrapes podinfo through the ServiceMonitor
#   2. our recording rules produce RED metrics
#   3. our alert rules are loaded
#   4. the Grafana dashboard is provisioned
#   5. injecting 40% errors fires HighErrorRate and it reaches Alertmanager
set -euo pipefail
cd "$(dirname "$0")/.."

NS=monitoring
REPORT=${REPORT:-e2e-metrics-report.md}
: > "$REPORT"

prom() {  # PromQL instant query through the API server proxy (no port-forward needed)
  kubectl get --raw "/api/v1/namespaces/$NS/services/kps-prometheus:9090/proxy/api/v1/query?query=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$1")"
}
count() { python3 -c 'import json,sys;print(len(json.load(sys.stdin)["data"]["result"]))'; }
first_value() { python3 -c 'import json,sys;r=json.load(sys.stdin)["data"]["result"];print(r[0]["value"][1] if r else "none")'; }

wait_for() {  # wait_for <description> <timeout-seconds> <command...>
  local what=$1 timeout=$2; shift 2
  local start; start=$(date +%s)
  until "$@"; do
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then echo "FAIL: $what (after ${timeout}s)"; exit 1; fi
    sleep 10
  done
  local took=$(( $(date +%s) - start ))
  echo "PASS: $what (${took}s)"
  echo "| $what | ✅ | ${took}s |" >> "$REPORT"
}

echo "| Check | Result | Time |" >> "$REPORT"
echo "|---|---|---|" >> "$REPORT"

targets_up()     { [ "$(prom 'up{namespace="demo", service="podinfo"} == 1' | count)" -ge 2 ]; }
red_metrics()    { [ "$(prom 'service:http_requests:rate5m{namespace="demo", service="podinfo"} > 0' | count)" -ge 1 ]; }
rules_loaded()   { kubectl get --raw "/api/v1/namespaces/$NS/services/kps-prometheus:9090/proxy/api/v1/rules" | grep -q '"HighErrorRate"'; }
GRAFANA_PW=$(kubectl -n "$NS" get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d)
kubectl -n "$NS" port-forward svc/kps-grafana 3000:80 >/tmp/grafana-port-forward.log 2>&1 &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null || true' EXIT
sleep 3
dashboard_ready() {
  curl -s -u "admin:${GRAFANA_PW}" 'http://127.0.0.1:3000/api/search?query=Service%20RED' \
    -o /tmp/grafana-search.json 2>/dev/null && grep -q '"uid":"service-red"' /tmp/grafana-search.json
}
alert_firing()   { [ "$(prom 'ALERTS{alertname="HighErrorRate", alertstate="firing", namespace="demo"}' | count)" -ge 1 ]; }
in_alertmanager() { kubectl get --raw "/api/v1/namespaces/$NS/services/kps-alertmanager:9093/proxy/api/v2/alerts?active=true" | grep -q '"alertname":"HighErrorRate"'; }

wait_for "Prometheus scrapes both podinfo pods"        300 targets_up
wait_for "Alert rules loaded into Prometheus"          120 rules_loaded
wait_for "Recording rules produce RED metrics"         300 red_metrics
wait_for "Grafana dashboard provisioned"               180 dashboard_ready

echo "Baseline error ratio: $(prom 'service:http_error_ratio:rate5m{namespace="demo"}' | first_value)"
echo ">> Injecting failures: 40% of requests -> HTTP 500"
kubectl -n demo set env deploy/traffic-generator ERROR_PERCENT=40
kubectl -n demo rollout status deploy/traffic-generator --timeout=2m

wait_for "HighErrorRate fires on 40% errors"           600 alert_firing
wait_for "Alert delivered to Alertmanager"             120 in_alertmanager
echo "Error ratio while failing: $(prom 'service:http_error_ratio:rate5m{namespace="demo"}' | first_value)"

kubectl -n demo set env deploy/traffic-generator ERROR_PERCENT=2 >/dev/null
echo
echo "ALL METRICS CHECKS PASSED"
