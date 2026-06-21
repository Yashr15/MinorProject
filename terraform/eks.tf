# Amazon EKS Cluster and Node Groups
#
# This creates:
# 1. EKS Cluster (managed Kubernetes control plane)
# 2. App Node Group (m7i-flex.large) — runs microservices
# 3. Infra Node Group (c7i-flex.large) — runs monitoring/infra
#
# Uses a local module for clean separation of concerns.

module "eks" {
  source = "./modules/eks"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  # IAM roles (from iam.tf)
  cluster_role_arn = aws_iam_role.eks_cluster.arn
  node_role_arn    = aws_iam_role.eks_nodes.arn

  # Networking (from vpc.tf)
  subnet_ids        = aws_subnet.private[*].id
  public_subnet_ids = aws_subnet.public[*].id

  # ─── Application Node Group (m7i-flex.large) ──
  app_node_instance_type = var.app_node_instance_type
  app_node_desired_count = var.app_node_desired_count
  app_node_min_count     = var.app_node_min_count
  app_node_max_count     = var.app_node_max_count

  # ─── Infrastructure Node Group (c7i-flex.large)
  infra_node_instance_type = var.infra_node_instance_type
  infra_node_desired_count = var.infra_node_desired_count
  infra_node_min_count     = var.infra_node_min_count
  infra_node_max_count     = var.infra_node_max_count

  # Tags
  project_name = var.project_name
  environment  = local.environment

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_worker_node,
    aws_iam_role_policy_attachment.eks_cni,
    aws_iam_role_policy_attachment.ecr_read,
  ]
}

# Allow Jenkins (and other VPC resources) to connect to EKS API server
resource "aws_security_group_rule" "jenkins_to_eks" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr] # Allows access from the VPC CIDR (including Jenkins EC2)
  security_group_id = module.eks.cluster_security_group_id
}

# Grant Jenkins administrative access to the EKS cluster
resource "aws_eks_access_entry" "jenkins" {
  count         = var.jenkins_iam_arn != "" ? 1 : 0
  cluster_name  = module.eks.cluster_name
  principal_arn = var.jenkins_iam_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "jenkins_admin" {
  count         = var.jenkins_iam_arn != "" ? 1 : 0
  cluster_name  = module.eks.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = var.jenkins_iam_arn

  access_scope {
    type = "cluster"
  }
}

