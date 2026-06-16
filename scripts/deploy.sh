#!/bin/bash
# ═══════════════════════════════════════════════════════════
# deploy.sh — Full deployment pipeline
# ═══════════════════════════════════════════════════════════
#
# This script runs the entire deployment:
#   1. Terraform init + apply (creates VPC, EKS, ECR, IAM)
#   2. Configure kubectl
#   3. Build all Docker images
#   4. Push images to ECR
#   5. Deploy to EKS
#   6. Install monitoring (Prometheus + Grafana)
#
# Usage:
#   ./scripts/deploy.sh              # Deploy with workspace 'dev'
#   ./scripts/deploy.sh staging      # Deploy with workspace 'staging'
#   ./scripts/deploy.sh prod         # Deploy with workspace 'prod'
# ═══════════════════════════════════════════════════════════

set -euo pipefail

# ─── Configuration ────────────────────────────────
WORKSPACE="${1:-dev}"
AWS_REGION="ap-south-1"
PROJECT_NAME="online-boutique"
CLUSTER_NAME="${PROJECT_NAME}-eks-${WORKSPACE}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}[✅]${NC} $1"; }
warn() { echo -e "${YELLOW}[⚠️]${NC} $1"; }
error() { echo -e "${RED}[❌]${NC} $1"; exit 1; }

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  🚀 Online Boutique — Full Deployment        ║"
echo "╠══════════════════════════════════════════════╣"
echo "║  Workspace:  ${WORKSPACE}                          ║"
echo "║  Region:     ${AWS_REGION}                    ║"
echo "║  Cluster:    ${CLUSTER_NAME}   ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ─── Pre-flight Checks ───────────────────────────
log "Running pre-flight checks..."

command -v aws >/dev/null 2>&1 || error "AWS CLI not installed"
command -v terraform >/dev/null 2>&1 || error "Terraform not installed"
command -v kubectl >/dev/null 2>&1 || error "kubectl not installed"
command -v docker >/dev/null 2>&1 || error "Docker not installed"

# Verify AWS credentials
aws sts get-caller-identity >/dev/null 2>&1 || error "AWS credentials not configured. Run 'aws configure'"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

success "Pre-flight checks passed (Account: ${AWS_ACCOUNT_ID})"

# ═══════════════════════════════════════════════════
# PHASE 1: TERRAFORM — Infrastructure
# ═══════════════════════════════════════════════════
log "Phase 1: Provisioning infrastructure with Terraform..."

cd "${PROJECT_ROOT}/terraform"

# Initialize Terraform
terraform init -input=false

# Select or create workspace
if terraform workspace list | grep -q "${WORKSPACE}"; then
    terraform workspace select "${WORKSPACE}"
else
    terraform workspace new "${WORKSPACE}"
fi

log "Using workspace: $(terraform workspace show)"

# Plan and apply
terraform plan \
    -var="environment=${WORKSPACE}" \
    -var="cluster_name=${CLUSTER_NAME}" \
    -out=tfplan

log "Applying Terraform plan..."
terraform apply -input=false tfplan

# Retrieve the actual cluster name dynamically from Terraform outputs
CLUSTER_NAME=$(terraform output -raw cluster_name)

success "Infrastructure provisioned! Cluster Name: ${CLUSTER_NAME}"

# ═══════════════════════════════════════════════════
# PHASE 2: CONFIGURE KUBECTL
# ═══════════════════════════════════════════════════
log "Phase 2: Configuring kubectl..."

aws eks update-kubeconfig \
    --region "${AWS_REGION}" \
    --name "${CLUSTER_NAME}"

kubectl cluster-info
success "kubectl configured for ${CLUSTER_NAME}"

# ═══════════════════════════════════════════════════
# PHASE 3: BUILD & PUSH DOCKER IMAGES
# ═══════════════════════════════════════════════════
log "Phase 3: Building and pushing Docker images..."

cd "${PROJECT_ROOT}"

# Login to ECR
aws ecr get-login-password --region "${AWS_REGION}" | \
    docker login --username AWS --password-stdin "${ECR_REGISTRY}"

# List of all services
ALL_SERVICES=(
    "emailservice"
    "productcatalogservice"
    "recommendationservice"
    "shippingservice"
    "checkoutservice"
    "paymentservice"
    "currencyservice"
    "cartservice"
    "frontend"
    "adservice"
    "loadgenerator"
)

IMAGE_TAG="$(git rev-parse --short HEAD 2>/dev/null || echo 'latest')"

for SERVICE in "${ALL_SERVICES[@]}"; do
    case "${SERVICE}" in
        "cartservice")
            CONTEXT="src/cartservice/src"
            ;;
        *)
            CONTEXT="src/${SERVICE}"
            ;;
    esac
    ECR_REPO="${ECR_REGISTRY}/${PROJECT_NAME}/${SERVICE}"

    log "  🔨 Building ${SERVICE}..."
    docker build \
        --platform linux/amd64 \
        -t "${ECR_REPO}:${IMAGE_TAG}" \
        -t "${ECR_REPO}:latest" \
        "${CONTEXT}"

    log "  📤 Pushing ${SERVICE}..."
    docker push "${ECR_REPO}:${IMAGE_TAG}"
    docker push "${ECR_REPO}:latest"

    success "  ${SERVICE} → ${ECR_REPO}:${IMAGE_TAG}"
done

success "All images built and pushed!"

# ═══════════════════════════════════════════════════
# PHASE 4: DEPLOY TO EKS
# ═══════════════════════════════════════════════════
log "Phase 4: Deploying to EKS..."

cd "${PROJECT_ROOT}"

for SERVICE in "${ALL_SERVICES[@]}"; do
    ECR_IMAGE="${ECR_REGISTRY}/${PROJECT_NAME}/${SERVICE}:${IMAGE_TAG}"
    sed -i.bak -E "s|image:[[:space:]]*([^[:space:]]+/)?${SERVICE}(:[^[:space:]]+)?([[:space:]]+.*)?$|image: ${ECR_IMAGE}|g" \
        "kubernetes-manifests/${SERVICE}.yaml" 2>/dev/null || true
done

# Clean up .bak files
find kubernetes-manifests -name "*.bak" -delete 2>/dev/null || true

# Apply all manifests
kubectl apply -k kubernetes-manifests/

# Wait for deployments
log "Waiting for deployments to be ready..."
kubectl rollout status deployment/frontend --timeout=180s
kubectl rollout status deployment/cartservice --timeout=180s

success "All services deployed!"

# ═══════════════════════════════════════════════════
# PHASE 5: INSTALL MONITORING
# ═══════════════════════════════════════════════════
log "Phase 5: Installing Prometheus + Grafana..."

if command -v helm >/dev/null 2>&1; then
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
    helm repo update

    helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
        --namespace monitoring --create-namespace \
        -f monitoring/prometheus-values.yaml \
        --wait --timeout 300s

    success "Monitoring installed!"
else
    warn "Helm not installed — skipping monitoring setup"
    warn "Install Helm: https://helm.sh/docs/intro/install/"
fi

# ═══════════════════════════════════════════════════
# DONE!
# ═══════════════════════════════════════════════════
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  🎉 DEPLOYMENT COMPLETE!                            ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║                                                      ║"
echo "║  Frontend URL:                                       ║"

FRONTEND_URL=$(kubectl get svc frontend-external -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending...")
echo "║  → http://${FRONTEND_URL}                 ║"
echo "║                                                      ║"
echo "║  Grafana:                                            ║"
echo "║  → kubectl port-forward svc/monitoring-grafana       ║"
echo "║    3000:80 -n monitoring                             ║"
echo "║  → Login: admin / prom-operator                      ║"
echo "║                                                      ║"
echo "╚══════════════════════════════════════════════════════╝"
