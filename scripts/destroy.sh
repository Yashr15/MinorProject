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

# ─── Step 3: Clean Dangling Cloud Resources ───────
log "Step 3: Cleaning up dangling cloud resources (ELBs, security groups)..."

AWS_ACCOUNT_ID=""
if command -v aws >/dev/null 2>&1; then
    if aws sts get-caller-identity >/dev/null 2>&1; then
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    fi
fi

if [ -n "${AWS_ACCOUNT_ID}" ]; then
    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Project,Values=${PROJECT_NAME}" "Name=tag:Workspace,Values=${WORKSPACE}" \
        --query "Vpcs[0].VpcId" \
        --output text \
        --region "${AWS_REGION}" 2>/dev/null || echo "None")

    if [ "${VPC_ID}" != "None" ] && [ -n "${VPC_ID}" ] && [ "${VPC_ID}" != "null" ]; then
        log "Found active VPC: ${VPC_ID}. Checking for dangling resources..."

        # 1. Delete Classic ELBs in this VPC
        CLASSIC_ELBS=$(aws elb describe-load-balancers --region "${AWS_REGION}" --query "LoadBalancerDescriptions[?VPCId=='${VPC_ID}'].LoadBalancerName" --output text 2>/dev/null || echo "")
        for ELB in ${CLASSIC_ELBS}; do
            warn "Deleting dangling Classic ELB: ${ELB}"
            aws elb delete-load-balancer --load-balancer-name "${ELB}" --region "${AWS_REGION}" || true
        done

        # 2. Delete Application/Network ELBs (v2) in this VPC
        V2_ELBS=$(aws elbv2 describe-load-balancers --region "${AWS_REGION}" --query "LoadBalancers[?VpcId=='${VPC_ID}'].LoadBalancerArn" --output text 2>/dev/null || echo "")
        for ELB_ARN in ${V2_ELBS}; do
            warn "Deleting dangling ALB/NLB: ${ELB_ARN}"
            aws elbv2 delete-load-balancer --load-balancer-arn "${ELB_ARN}" --region "${AWS_REGION}" || true
        done

        # Give AWS a few seconds to begin detaching ENIs
        if [ -n "${CLASSIC_ELBS}" ] || [ -n "${V2_ELBS}" ]; then
            log "Waiting for load balancer deletion and ENI release..."
            sleep 15
        fi

        # 3. Delete custom security groups
        CUSTOM_SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${VPC_ID}" --region "${AWS_REGION}" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text 2>/dev/null || echo "")
        for SG in ${CUSTOM_SGS}; do
            warn "Deleting custom security group: ${SG}"
            aws ec2 delete-security-group --group-id "${SG}" --region "${AWS_REGION}" || true
        done
    fi
else
    warn "AWS CLI or credentials not configured — skipping dangling resource cleanup"
fi

# ─── Step 4: Terraform Destroy ────────────────────
log "Step 4: Destroying Terraform infrastructure..."

cd "${PROJECT_ROOT}/terraform"

if [ -n "${AWS_ACCOUNT_ID}" ]; then
    terraform init -input=false -backend-config="bucket=online-boutique-terraform-state-${AWS_ACCOUNT_ID}"
else
    terraform init -input=false
fi

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

# ─── Step 5: Switch back to default workspace ─────
terraform workspace select default
log "Switched to default workspace"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  ✅ All resources destroyed!                 ║"
echo "╚══════════════════════════════════════════════╝"
