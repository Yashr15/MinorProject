# EKS Module — creates the cluster and TWO managed node groups
#
# Node Group 1: "app-nodes"   — m7i-flex.large (runs microservices)
# Node Group 2: "infra-nodes" — c7i-flex.large (runs monitoring/infra)

resource "aws_eks_cluster" "this" {
  name                          = var.cluster_name
  role_arn                      = var.cluster_role_arn
  version                       = var.cluster_version
  bootstrap_self_managed_addons = false

  vpc_config {
    subnet_ids              = concat(var.subnet_ids, var.public_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = true # Set to false in production
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = {
    Name = var.cluster_name
  }
}

# ─── Node Group 1: Application Nodes (m7i-flex.large) ────
# These run the 11 microservice pods

resource "aws_eks_node_group" "app_nodes" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-app-nodes"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.subnet_ids # Private subnets

  instance_types = [var.app_node_instance_type]

  scaling_config {
    desired_size = var.app_node_desired_count
    min_size     = var.app_node_min_count
    max_size     = var.app_node_max_count
  }

  update_config {
    max_unavailable = 1
  }

  # Labels so you can target pods to specific node groups
  labels = {
    "role"        = "application"
    "node-group"  = "app-nodes"
  }

  tags = {
    Name        = "${var.cluster_name}-app-node"
    Role        = "application"
    NodeGroup   = "app-nodes"
    Project     = var.project_name
    Environment = var.environment
  }

  depends_on = [aws_eks_cluster.this]
}

# ─── Node Group 2: Infrastructure Nodes (c7i-flex.large) ─
# Runs Prometheus, Grafana, and other infra workloads

resource "aws_eks_node_group" "infra_nodes" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-infra-nodes"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.subnet_ids # Private subnets

  instance_types = [var.infra_node_instance_type]

  scaling_config {
    desired_size = var.infra_node_desired_count
    min_size     = var.infra_node_min_count
    max_size     = var.infra_node_max_count
  }

  update_config {
    max_unavailable = 1
  }

  # Labels for targeting monitoring pods to infra nodes
  labels = {
    "role"        = "infrastructure"
    "node-group"  = "infra-nodes"
  }

  # Taint: only pods that tolerate this taint will schedule here
  # This prevents microservice pods from landing on infra nodes
  taint {
    key    = "dedicated"
    value  = "infrastructure"
    effect = "NO_SCHEDULE"
  }

  tags = {
    Name        = "${var.cluster_name}-infra-node"
    Role        = "infrastructure"
    NodeGroup   = "infra-nodes"
    Project     = var.project_name
    Environment = var.environment
  }

  depends_on = [aws_eks_cluster.this]
}
