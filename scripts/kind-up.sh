#!/usr/bin/env bash
set -euo pipefail
CLUSTER=${CLUSTER:-observability}
for bin in kind kubectl helm; do
  command -v "$bin" >/dev/null || { echo "Missing '$bin' - please install it first."; exit 1; }
done
if ! kind get clusters | grep -qx "$CLUSTER"; then
  kind create cluster --name "$CLUSTER" --wait 120s
fi
kubectl config use-context "kind-$CLUSTER" >/dev/null
echo "kind cluster '$CLUSTER' is ready"
