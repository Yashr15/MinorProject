# EKS Module Variables

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster"
}

variable "cluster_version" {
  type        = string
  description = "Kubernetes version"
}

variable "cluster_role_arn" {
  type        = string
  description = "IAM role ARN for the EKS cluster"
}

variable "node_role_arn" {
  type        = string
  description = "IAM role ARN for the worker nodes"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for worker nodes"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs for cluster API endpoint"
}

# ─── Application Node Group ─────────────────────

variable "app_node_instance_type" {
  type        = string
  description = "EC2 instance type for application nodes (m7i-flex.large)"
}

variable "app_node_desired_count" {
  type        = number
  description = "Desired number of application nodes"
}

variable "app_node_min_count" {
  type        = number
  description = "Minimum number of application nodes"
}

variable "app_node_max_count" {
  type        = number
  description = "Maximum number of application nodes"
}

# ─── Infrastructure Node Group ──────────────────

variable "infra_node_instance_type" {
  type        = string
  description = "EC2 instance type for infrastructure nodes (c7i-flex.large)"
}

variable "infra_node_desired_count" {
  type        = number
  description = "Desired number of infrastructure nodes"
}

variable "infra_node_min_count" {
  type        = number
  description = "Minimum number of infrastructure nodes"
}

variable "infra_node_max_count" {
  type        = number
  description = "Maximum number of infrastructure nodes"
}

# ─── Tags ────────────────────────────────────────

variable "project_name" {
  type        = string
  description = "Project name for tagging"
}

variable "environment" {
  type        = string
  description = "Environment name for tagging"
}
