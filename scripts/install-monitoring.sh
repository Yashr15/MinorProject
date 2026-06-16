#!/bin/bash
# ═══════════════════════════════════════════════════════════
# install-monitoring.sh — Install Prometheus + Grafana
# ═══════════════════════════════════════════════════════════
#
# Run after EKS is up and kubectl is configured.
#
# Usage: ./scripts/install-monitoring.sh
# ═══════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

echo "📊 Installing Prometheus + Grafana..."

# Check prerequisites
command -v helm >/dev/null 2>&1 || { echo "❌ Helm not installed"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl not installed"; exit 1; }

# Add Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update

# Install / upgrade
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --create-namespace \
    -f "${PROJECT_ROOT}/monitoring/prometheus-values.yaml" \
    --wait --timeout 300s

echo ""
echo "✅ Monitoring installed!"
echo ""
echo "Access Grafana:"
echo "  kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring"
echo "  Open: http://localhost:3000"
echo "  Login: admin / prom-operator"
echo ""
echo "Access Prometheus:"
echo "  kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring"
echo "  Open: http://localhost:9090"
