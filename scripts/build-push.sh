#!/bin/bash
# ═══════════════════════════════════════════════════════════
# build-push.sh — Build and push Docker images only
# ═══════════════════════════════════════════════════════════
#
# Use this when you only want to rebuild images without
# re-running Terraform. Useful for code changes.
#
# Usage:
#   ./scripts/build-push.sh                    # Build ALL services
#   ./scripts/build-push.sh frontend           # Build only frontend
#   ./scripts/build-push.sh frontend cartservice  # Build specific services
# ═══════════════════════════════════════════════════════════

set -euo pipefail

AWS_REGION="ap-south-1"
PROJECT_NAME="online-boutique"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
IMAGE_TAG="$(git -C "${PROJECT_ROOT}" rev-parse --short HEAD 2>/dev/null || echo 'latest')"

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

# Determine which services to build
if [ $# -eq 0 ]; then
    SERVICES=("${ALL_SERVICES[@]}")
    echo "🔨 Checking all services for changes..."
else
    SERVICES=("$@")
    echo "🔨 Checking selected services: ${SERVICES[*]}..."
fi

# Login to ECR
echo "🔐 Logging into ECR..."
aws ecr get-login-password --region "${AWS_REGION}" | \
    docker login --username AWS --password-stdin "${ECR_REGISTRY}"

cd "${PROJECT_ROOT}"

FAILED=()
for SERVICE in "${SERVICES[@]}"; do
    case "${SERVICE}" in
        "cartservice")
            CONTEXT="src/cartservice/src"
            ;;
        "emailservice"|"productcatalogservice"|"recommendationservice"|"shippingservice"|"checkoutservice"|"paymentservice"|"currencyservice"|"frontend"|"adservice"|"loadgenerator")
            CONTEXT="src/${SERVICE}"
            ;;
        *)
            echo "❌ Unknown service: ${SERVICE}"
            FAILED+=("${SERVICE}")
            continue
            ;;
    esac

    SVC_TAG="$(git log -1 --format="%h" -- "${CONTEXT}" 2>/dev/null || echo 'latest')"
    ECR_REPO="${ECR_REGISTRY}/${PROJECT_NAME}/${SERVICE}"

    echo ""
    echo "─── Processing ${SERVICE} ───"
    if aws ecr describe-images --repository-name "${PROJECT_NAME}/${SERVICE}" --image-ids imageTag="${SVC_TAG}" >/dev/null 2>&1; then
        echo "⏭️ Image ${ECR_REPO}:${SVC_TAG} already exists in ECR. Skipping build and push."
    else
        echo "🔨 Building ${SERVICE} (tag: ${SVC_TAG})..."
        if docker build \
            --platform linux/amd64 \
            -t "${ECR_REPO}:${SVC_TAG}" \
            -t "${ECR_REPO}:latest" \
            "${CONTEXT}"; then

            echo "📤 Pushing ${SERVICE}..."
            docker push "${ECR_REPO}:${SVC_TAG}"
            docker push "${ECR_REPO}:latest"
            echo "✅ ${SERVICE} → ${ECR_REPO}:${SVC_TAG}"
        else
            echo "❌ Failed to build ${SERVICE}"
            FAILED+=("${SERVICE}")
        fi
    fi
done

echo ""
if [ ${#FAILED[@]} -eq 0 ]; then
    echo "✅ All services built and pushed successfully!"
else
    echo "❌ Failed services: ${FAILED[*]}"
    exit 1
fi
