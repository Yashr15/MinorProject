#!/bin/bash
# ═══════════════════════════════════════════════════════════
# destroy.sh — Tear down all infrastructure
# ═══════════════════════════════════════════════════════════
#
# This cleanly destroys everything in reverse order:
#   1. Delete K8s deployments
#   2. Uninstall monitoring
#   3. Terraform destroy (removes VPC, EKS, ECR, IAM)
#
# Usage:
#   ./scripts/destroy.sh              # Destroy workspace 'dev'
#   ./scripts/destroy.sh staging      # Destroy workspace 'staging'
# ═══════════════════════════════════════════════════════════

set -euo pipefail

WORKSPACE="${1:-dev}"
AWS_REGION="ap-south-1"
PROJECT_NAME="online-boutique"
CLUSTER_NAME="${PROJECT_NAME}-eks-${WORKSPACE}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}[✅]${NC} $1"; }
warn() { echo -e "${YELLOW}[⚠️]${NC} $1"; }

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  🗑️  DESTROYING INFRASTRUCTURE               ║"
echo "╠══════════════════════════════════════════════╣"
echo "║  Workspace: ${WORKSPACE}                           ║"
echo "║  Cluster:   ${CLUSTER_NAME}   ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo -e "${RED}⚠️  WARNING: This will DELETE everything!${NC}"
echo ""
read -p "Are you sure? Type 'yes' to confirm: " CONFIRM

if [ "${CONFIRM}" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

# ─── Step 1: Delete K8s Resources ─────────────────
log "Step 1: Deleting Kubernetes resources..."

if kubectl cluster-info >/dev/null 2>&1; then
    kubectl delete -k "${PROJECT_ROOT}/kubernetes-manifests/" --ignore-not-found=true || true
    success "K8s resources deleted"
else
    warn "kubectl not connected — skipping K8s cleanup"
fi

# ─── Step 2: Uninstall Monitoring ─────────────────
log "Step 2: Uninstalling monitoring..."

if command -v helm >/dev/null 2>&1; then
    helm uninstall monitoring -n monitoring 2>/dev/null || true
    kubectl delete namespace monitoring --ignore-not-found=true 2>/dev/null || true
    success "Monitoring uninstalled"
else
    warn "Helm not found — skipping"
fi

# ─── Step 3: Terraform Destroy ────────────────────
log "Step 3: Destroying Terraform infrastructure..."

cd "${PROJECT_ROOT}/terraform"

terraform init -input=false

if terraform workspace list | grep -q "${WORKSPACE}"; then
    terraform workspace select "${WORKSPACE}"
else
    warn "Workspace '${WORKSPACE}' not found"
    exit 1
fi

terraform destroy \
    -var="environment=${WORKSPACE}" \
    -var="cluster_name=${CLUSTER_NAME}" \
    -auto-approve

success "Terraform infrastructure destroyed"

# ─── Step 4: Switch back to default workspace ─────
terraform workspace select default
log "Switched to default workspace"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  ✅ All resources destroyed!                 ║"
echo "╚══════════════════════════════════════════════╝"
