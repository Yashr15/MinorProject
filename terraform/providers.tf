# Terraform provider configuration for AWS
#
# This file tells Terraform which cloud provider to use (AWS)
# and how to authenticate with Kubernetes (EKS).

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
  }

  # ─── Secure Remote State (S3 + DynamoDB) ──────
  # Run scripts/setup-backend.sh FIRST to create these resources
  #
  # S3 bucket  → stores terraform.tfstate (encrypted, versioned)
  # DynamoDB   → state locking (prevents concurrent modifications)
  #
  # NOTE: Replace <YOUR_AWS_ACCOUNT_ID> with your actual account ID
  # after running setup-backend.sh
  backend "s3" {
    bucket         = "online-boutique-terraform-state-553136990999"
    key            = "infrastructure/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "online-boutique-terraform-lock"
    encrypt        = true

    # Workspace-aware: each workspace gets its own state file
    # dev     → env:/dev/infrastructure/terraform.tfstate
    # staging → env:/staging/infrastructure/terraform.tfstate
    # prod    → env:/prod/infrastructure/terraform.tfstate
  }
}

# AWS Provider — uses your AWS CLI credentials
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# Kubernetes Provider — connects to EKS after it's created
# This lets Terraform deploy K8s resources directly if needed
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}
