# Input variables for the Online Boutique AWS infrastructure
#
# These variables let you customize the deployment without
# editing the main Terraform files. Override them in terraform.tfvars.

variable "aws_region" {
  type        = string
  description = "AWS region to deploy the infrastructure"
  default     = "ap-south-1" # Mumbai
}

variable "project_name" {
  type        = string
  description = "Name of the project (used for tagging and naming resources)"
  default     = "online-boutique"
}

variable "environment" {
  type        = string
  description = "Deployment environment — auto-set from Terraform workspace if not specified"
  default     = ""
}

# ─── EKS Configuration ──────────────────────────

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster"
  default     = "online-boutique-eks"
}

variable "cluster_version" {
  type        = string
  description = "Kubernetes version for EKS"
  default     = "1.30"
}

# ─── Node Group: Application (m7i-flex.large) ───
# Runs the 11 microservices on EKS

variable "app_node_instance_type" {
  type        = string
  description = "EC2 instance type for application workloads (EKS microservices)"
  default     = "m7i-flex.large" # 2 vCPU, 8GB RAM — for microservices
}

variable "app_node_desired_count" {
  type        = number
  description = "Desired number of application worker nodes"
  default     = 2
}

variable "app_node_min_count" {
  type        = number
  description = "Minimum number of application worker nodes"
  default     = 1
}

variable "app_node_max_count" {
  type        = number
  description = "Maximum number of application worker nodes"
  default     = 3
}

# ─── Node Group: Infra/Monitoring (c7i-flex.large) ─
# Runs Prometheus, Grafana, and other infra workloads

variable "infra_node_instance_type" {
  type        = string
  description = "EC2 instance type for infrastructure workloads (monitoring, Jenkins agent)"
  default     = "c7i-flex.large" # 2 vCPU, 4GB RAM — compute-optimized for monitoring
}

variable "infra_node_desired_count" {
  type        = number
  description = "Desired number of infrastructure worker nodes"
  default     = 1
}

variable "infra_node_min_count" {
  type        = number
  description = "Minimum number of infrastructure worker nodes"
  default     = 1
}

variable "infra_node_max_count" {
  type        = number
  description = "Maximum number of infrastructure worker nodes"
  default     = 2
}

# ─── Networking ──────────────────────────────────

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

# ─── ECR (Container Registry) ───────────────────

variable "microservices" {
  type        = list(string)
  description = "List of microservice names — one ECR repo per service"
  default = [
    "adservice",
    "cartservice",
    "checkoutservice",
    "currencyservice",
    "emailservice",
    "frontend",
    "loadgenerator",
    "paymentservice",
    "productcatalogservice",
    "recommendationservice",
    "shippingservice"
  ]
}

variable "jenkins_iam_arn" {
  type        = string
  description = "The AWS IAM User or Role ARN that Jenkins uses to deploy to EKS (e.g., arn:aws:iam::123456789012:user/jenkins)"
  default     = ""
}

variable "additional_admin_arns" {
  type        = list(string)
  description = "Additional AWS IAM User/Role ARNs (e.g. developers' local profiles) to grant admin access to the EKS cluster"
  default     = []
}

