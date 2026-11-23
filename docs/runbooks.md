# Runbooks

Each alert links here through its `runbook_url` annotation. A runbook answers
three questions for whoever is on call: what it means, how to confirm it, and
how to fix it.

## HighErrorRate

**Meaning:** more than 5% of a service's requests returned 5xx for 2 minutes (with at least 0.1 req/s, so a single failure on an idle service doesn't page anyone). Severity: **critical**.

**Confirm**
1. Grafana → *Services / Service RED overview* → select the service. Check whether the error spike lines up with a deploy.
2. Kibana → data view `k8s-logs-*` → filter `kubernetes.namespace_name: <ns> and kubernetes.labels.app: <service> and level: error`.
3. `kubectl -n <ns> get pods` to look for restarts or pods that aren't Ready.

**Mitigate**
- If it started with a deploy, roll back (`kubectl rollout undo deploy/<name>`, or revert the GitOps commit).
- If a dependency is failing (database, external API), fail over or degrade gracefully, and tell the owning team.

## HighLatencyP95

**Meaning:** the 95th-percentile response time has been above 500 ms for 5 minutes. Severity: warning.

**Confirm:** check the latency percentiles panel and see whether p50 moved too (everything is slow) or only p95/p99 (a slow path or a slow dependency). Then check CPU throttling and memory on the pods panels.

**Mitigate:** scale out (`kubectl scale` or check the HPA), raise CPU limits if the pods are throttled, or find the slow endpoint in the *Requests by path* panel.

## ServiceNoTraffic

**Meaning:** a scraped service has received zero requests for 10 minutes. Severity: warning.

**Confirm:** check the Ingress or load balancer, DNS, and the upstream callers. `kubectl -n <ns> get endpoints <service>`: an empty list means no Ready pods behind the Service.

## ContainerMemoryNearLimit

**Meaning:** a container has been using more than 90% of its memory limit for 5 minutes. It will be OOM-killed if usage keeps growing.

**Confirm:** check the memory panel for a steady climb (leak) or a plateau (the limit is too low).

**Mitigate:** raise the limit as a short-term fix, then investigate the leak. Check for `OOMKilled` in `kubectl describe pod`.

## PodRestartingFrequently

**Meaning:** a container restarted more than 3 times in 15 minutes.

**Confirm:** `kubectl -n <ns> describe pod <pod>` (look at Last State and Reason) and `kubectl -n <ns> logs <pod> --previous`.

**Common causes:** OOMKilled (see above), failing liveness probe, a missing config or Secret, or a crash on startup after a deploy.
