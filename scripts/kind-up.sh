#!/usr/bin/env bash
# Run the full stack locally on kind: the app chart, Prometheus + Grafana with the committed dashboard,
# and metrics-server for the HPA. Everything except the AWS-only pieces (ALB, WAF, Secrets Manager).
#
# Requires: docker, kind, kubectl, helm.   Tear down with: scripts/kind-down.sh
set -euo pipefail

HELM=${HELM:-helm}
CLUSTER=accounts-api
NS=accounts-api
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if ! kind get clusters | grep -qx "$CLUSTER"; then
  kind create cluster --config deploy/kind/cluster.yaml --wait 120s
fi
kubectl config use-context "kind-$CLUSTER" >/dev/null

echo "==> Building and loading the image"
docker build -t accounts-api:local .
kind load docker-image accounts-api:local --name "$CLUSTER"

echo "==> Installing metrics-server and kube-prometheus-stack"
$HELM repo add metrics-server https://kubernetes-sigs.github.io/metrics-server >/dev/null
$HELM repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
$HELM repo update >/dev/null
# kind kubelets use self-signed certificates.
$HELM upgrade --install metrics-server metrics-server/metrics-server --version 3.14.0 \
  -n kube-system --set 'args={--kubelet-insecure-tls}' --wait
$HELM upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack --version 92.13.1 \
  -n monitoring --create-namespace -f observability/kube-prometheus-stack-values.yaml --wait --timeout 10m

kubectl -n monitoring create configmap accounts-api-dashboard \
  --from-file=accounts-api.json=observability/dashboards/accounts-api.json \
  --dry-run=client -o yaml | kubectl label --local -f - grafana_dashboard=1 -o yaml | kubectl apply -f -

echo "==> Preparing the app namespace (Pod Security 'restricted', local API key)"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$NS" --overwrite \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted
if ! kubectl -n "$NS" get secret accounts-api-auth-local >/dev/null 2>&1; then
  kubectl -n "$NS" create secret generic accounts-api-auth-local \
    --from-literal=API_KEY="$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
fi

echo "==> Deploying the app"
$HELM upgrade --install accounts-api deploy/helm/accounts-api -n "$NS" \
  -f deploy/helm/accounts-api/values-local.yaml --set-string podAnnotations.rolloutId="$(date +%s)" --wait --timeout 5m

cat <<EOF

Done. Try it:
  kubectl -n $NS port-forward svc/accounts-api 8080:80 &
  API_KEY=\$(kubectl -n $NS get secret accounts-api-auth-local -o jsonpath='{.data.API_KEY}' | base64 -d)
  curl -H "x-api-key: \$API_KEY" http://localhost:8080/getAccount

Grafana (admin password below), dashboard "Accounts API":
  kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3001:80 &
  kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d
EOF
