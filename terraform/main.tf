# Terraform main.tf — orchestrates all modules and resources
#
# This is the entry point for `terraform apply`.
# It ties together VPC, EKS, ECR, and IAM resources
# defined in their respective files.

# ─── Workspace-Aware Configuration ──────────────
# Terraform workspaces let you manage multiple environments
# (dev, staging, prod) from the same code.
#
# Usage:
#   terraform workspace new dev
#   terraform workspace new staging
#   terraform workspace new prod
#   terraform workspace select dev

locals {
  # Use workspace name as environment, or fall back to variable
  environment = var.environment != "" ? var.environment : terraform.workspace

  common_tags = {
    Project     = var.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
    Workspace   = terraform.workspace
  }

  # Workspace-aware naming — prevents resource name collisions
  # dev     → online-boutique-eks-dev
  # staging → online-boutique-eks-staging
  # prod    → online-boutique-eks-prod
  cluster_name = "${var.cluster_name}-${local.environment}"
}

# ─── Data Sources ────────────────────────────────

# Get current AWS account ID (used for ECR URLs in Jenkinsfile)
data "aws_caller_identity" "current" {}

# ─── Account Info Output ─────────────────────────

output "aws_account_id" {
  description = "AWS Account ID (needed for ECR login in Jenkins)"
  value       = data.aws_caller_identity.current.account_id
}

output "workspace" {
  description = "Current Terraform workspace"
  value       = terraform.workspace
}

output "environment" {
  description = "Current environment (derived from workspace)"
  value       = local.environment
}
