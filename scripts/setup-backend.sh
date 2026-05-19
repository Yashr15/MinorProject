#!/bin/bash
# ═══════════════════════════════════════════════════════════
# setup-backend.sh — Creates S3 bucket + DynamoDB table for
#                     Terraform remote state management
# ═══════════════════════════════════════════════════════════
#
# Run this ONCE before your first `terraform init`
# This script creates:
#   1. S3 bucket     → stores terraform.tfstate securely
#   2. DynamoDB table → prevents concurrent state modifications
#
# Usage: ./scripts/setup-backend.sh
# ═══════════════════════════════════════════════════════════

set -euo pipefail

# ─── Configuration ────────────────────────────────
AWS_REGION="ap-south-1"
PROJECT_NAME="online-boutique"
BUCKET_NAME="${PROJECT_NAME}-terraform-state-$(aws sts get-caller-identity --query Account --output text)"
DYNAMODB_TABLE="${PROJECT_NAME}-terraform-lock"

echo "╔══════════════════════════════════════════════╗"
echo "║  Setting up Terraform Remote State Backend   ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "  Region:   ${AWS_REGION}"
echo "  Bucket:   ${BUCKET_NAME}"
echo "  DynamoDB:  ${DYNAMODB_TABLE}"
echo ""

# ─── Step 1: Create S3 Bucket ─────────────────────
echo "📦 Creating S3 bucket for state storage..."

if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
    echo "   ✅ Bucket already exists"
else
    aws s3api create-bucket \
        --bucket "${BUCKET_NAME}" \
        --region "${AWS_REGION}" \
        --create-bucket-configuration LocationConstraint="${AWS_REGION}"

    # Enable versioning (keeps history of all state changes)
    aws s3api put-bucket-versioning \
        --bucket "${BUCKET_NAME}" \
        --versioning-configuration Status=Enabled

    # Enable encryption at rest
    aws s3api put-bucket-encryption \
        --bucket "${BUCKET_NAME}" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                },
                "BucketKeyEnabled": true
            }]
        }'

    # Block all public access
    aws s3api put-public-access-block \
        --bucket "${BUCKET_NAME}" \
        --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

    echo "   ✅ Bucket created with versioning + encryption + public access blocked"
fi

# ─── Step 2: Create DynamoDB Table ────────────────
echo "🔒 Creating DynamoDB table for state locking..."

if aws dynamodb describe-table --table-name "${DYNAMODB_TABLE}" --region "${AWS_REGION}" 2>/dev/null; then
    echo "   ✅ DynamoDB table already exists"
else
    aws dynamodb create-table \
        --table-name "${DYNAMODB_TABLE}" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "${AWS_REGION}"

    echo "   ⏳ Waiting for table to become active..."
    aws dynamodb wait table-exists --table-name "${DYNAMODB_TABLE}" --region "${AWS_REGION}"
    echo "   ✅ DynamoDB table created"
fi

# ─── Done ─────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  ✅ Backend setup complete!                  ║"
echo "╠══════════════════════════════════════════════╣"
echo "║                                              ║"
echo "║  Next steps:                                 ║"
echo "║  1. cd terraform                             ║"
echo "║  2. terraform init                           ║"
echo "║  3. terraform workspace new dev              ║"
echo "║  4. terraform plan                           ║"
echo "║  5. terraform apply                          ║"
echo "║                                              ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "Your backend config (already in providers.tf):"
echo "  bucket         = \"${BUCKET_NAME}\""
echo "  dynamodb_table = \"${DYNAMODB_TABLE}\""
echo "  region         = \"${AWS_REGION}\""
