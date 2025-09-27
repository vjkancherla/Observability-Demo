#!/bin/bash
set -e

echo "Creating k3d cluster..."
k3d cluster delete mycluster 2>/dev/null || true
k3d cluster create mycluster --agents 1 --wait
echo "   Cluster ready"

echo "Adding helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
helm repo update >/dev/null
echo "   Repositories updated"

echo "Creating namespaces..."
kubectl create namespace observability 2>/dev/null || true
kubectl create namespace my-demo 2>/dev/null || true
echo "   Namespaces observability and my-demo created"

wait_for_release() {
  release=$1
  namespace=$2
  echo "   Waiting for pods of release '$release' in namespace '$namespace' to be ready..."
  kubectl rollout status -n "$namespace" deployment -l app.kubernetes.io/instance=$release --timeout=5m || true
  kubectl rollout status -n "$namespace" statefulset -l app.kubernetes.io/instance=$release --timeout=5m || true
}

echo "Deploying Prometheus (v72.5.1)..."
helm upgrade --install dev-prometheus prometheus-community/kube-prometheus-stack \
  --version 72.5.1 --namespace observability -f values/prometheus.yaml --wait --timeout=5m
wait_for_release dev-prometheus observability
echo "   Prometheus deployed"

echo "Deploying Pushgateway..."
helm upgrade --install prometheus-pushgateway prometheus-community/prometheus-pushgateway \
  --version 3.4.1 --namespace observability -f values/pushgateway.yaml --wait --timeout=5m
wait_for_release prometheus-pushgateway observability
echo "   Pushgateway deployed"

echo "Deploying Loki (6.40.0)..."
helm upgrade --install dev-loki grafana/loki \
  --version 6.40.0 --namespace observability -f values/loki.yaml --wait --timeout=5m
wait_for_release dev-loki observability
echo "   Loki deployed"

echo "Deploying Promtail (6.17.0)..."
helm upgrade --install dev-promtail grafana/promtail \
  --version 6.17.0 --namespace observability -f values/promtail.yaml --wait --timeout=5m
wait_for_release dev-promtail observability
echo "   Promtail deployed"

echo "Deploying Grafana (v9.0.0)..."
helm upgrade --install dev-grafana grafana/grafana \
  --version 9.0.0 --namespace observability -f values/grafana.yaml --wait --timeout=5m
wait_for_release dev-grafana observability
echo "   Grafana deployed"

echo "Applying custom PrometheusRules and AlertmanagerConfig..."
kubectl apply -f alerts/preometheus-rules-cronjob-alerts.yaml
kubectl apply -f alerts/alertmanager-webhook.yaml
echo "   Custom rules and Alertmanager config applied"

echo "Deploying Tracing App..."
helm upgrade --install dev-tracing ./tracing-app-helm-chart \
  --namespace my-demo --wait --timeout=5m
wait_for_release dev-tracing my-demo
echo "   Tracing app deployed"

# Update the port-forward section
echo "Starting port-forwards..."
kubectl port-forward -n observability svc/dev-grafana 3000:80 >/dev/null 2>&1 &
kubectl port-forward -n observability svc/dev-prometheus-kube-promet-prometheus 9090:9090 >/dev/null 2>&1 &
kubectl port-forward -n observability svc/dev-prometheus-kube-promet-alertmanager 9093:9093 >/dev/null 2>&1 &
kubectl port-forward -n observability svc/prometheus-pushgateway 9091:9091 >/dev/null 2>&1 &
echo "   Port-forwards started (Grafana:3000, Prometheus:9090, Alertmanager:9093, Pushgateway:9091)"

echo ""
echo "Deployment complete!"
echo "   Grafana: http://localhost:3000 (admin/admin)"
echo "   Prometheus: http://localhost:9090"
echo "   Alertmanager: http://localhost:9093"
echo "   Pushgateway: http://localhost:9091"
echo "   Stop: ./cleanup.sh"