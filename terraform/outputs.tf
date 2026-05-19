# Terraform Outputs
#
# These values are printed after `terraform apply` and can be used
# in scripts and Jenkins pipelines.

# ─── EKS Cluster ─────────────────────────────────

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_region" {
  description = "AWS region where the cluster is deployed"
  value       = var.aws_region
}

# ─── kubectl Configuration Command ──────────────
# Run this command after terraform apply to configure kubectl

output "kubectl_configure" {
  description = "Command to configure kubectl for this cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${local.cluster_name}"
}

# ─── ECR Repositories ───────────────────────────

output "ecr_repo_urls" {
  description = "ECR repository URLs for all microservices"
  value = {
    for name, repo in aws_ecr_repository.microservices :
    name => repo.repository_url
  }
}

# ─── VPC ─────────────────────────────────────────

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}
