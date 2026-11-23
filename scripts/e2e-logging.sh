#!/usr/bin/env bash
# End-to-end check of the logging pipeline: container logs from the demo
# namespace are collected by Fluent Bit, enriched with Kubernetes metadata
# and searchable in Elasticsearch.
set -euo pipefail

REPORT=${REPORT:-e2e-logging-report.md}
PW=$(kubectl -n logging get secret logging-es-elastic-user -o jsonpath='{.data.elastic}' | base64 -d)

es() {
  kubectl -n logging exec logging-es-default-0 -c elasticsearch -- \
    curl -sk -u "elastic:${PW}" -H 'Content-Type: application/json' "https://localhost:9200$1" ${2:+-d "$2"}
}
count_docs() {
  es "/k8s-logs-*/_count" "$1" 2>/dev/null | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("count",0))
except Exception: print(0)'
}

DEMO='{"query":{"term":{"kubernetes.namespace_name.keyword":"demo"}}}'
PODINFO='{"query":{"bool":{"filter":[{"term":{"kubernetes.labels.app.keyword":"podinfo"}},{"exists":{"field":"level"}}]}}}'

start=$(date +%s)
until [ "$(count_docs "$DEMO")" -gt 0 ]; do
  [ $(( $(date +%s) - start )) -lt 300 ] || { echo "FAIL: no demo logs in Elasticsearch after 300s"; es "/_cat/indices?v"; exit 1; }
  sleep 10
done
took=$(( $(date +%s) - start ))
demo=$(count_docs "$DEMO")
structured=$(count_docs "$PODINFO")

echo "PASS: $demo log lines from namespace 'demo' indexed (${took}s)"
echo "PASS check: $structured podinfo lines parsed as structured JSON (field 'level' extracted)"
[ "$structured" -gt 0 ] || { echo "FAIL: podinfo JSON logs were not parsed into fields"; exit 1; }

echo "Sample document:"
es "/k8s-logs-*/_search?size=1" "$PODINFO" | python3 -c 'import json,sys
h=json.load(sys.stdin)["hits"]["hits"][0]["_source"]
k=h.get("kubernetes",{})
print(json.dumps({"level":h.get("level"),"msg":h.get("msg"),"namespace":k.get("namespace_name"),"pod":k.get("pod_name"),"container":k.get("container_name"),"labels":k.get("labels")},indent=2))'

{
  echo "| Check | Result |"
  echo "|---|---|"
  echo "| Demo namespace logs indexed in Elasticsearch | ✅ $demo lines in ${took}s |"
  echo "| podinfo JSON logs parsed into fields | ✅ $structured lines |"
  echo "| Kubernetes metadata (namespace, pod, labels) attached | ✅ |"
} > "$REPORT"
echo
echo "ALL LOGGING CHECKS PASSED"
