# IAM Roles for EKS
#
# EKS needs two IAM roles:
# 1. Cluster Role    — allows EKS service to manage AWS resources
# 2. Node Group Role — allows worker nodes to join cluster & pull images from ECR
#
# Workspace-aware naming prevents collisions between environments.

# ─── EKS Cluster IAM Role ───────────────────────

resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-eks-cluster-role-${local.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-eks-cluster-role-${local.environment}"
  }
}

# Attach the AWS managed policy for EKS clusters
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# ─── EKS Node Group IAM Role ────────────────────

resource "aws_iam_role" "eks_nodes" {
  name = "${var.project_name}-eks-node-role-${local.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-eks-node-role-${local.environment}"
  }
}

# Worker nodes need these 3 policies:
# 1. EKSWorkerNodePolicy      — lets nodes join the cluster
# 2. EKS_CNI_Policy           — lets nodes manage pod networking
# 3. EC2ContainerRegistryRead — lets nodes pull images from ECR

resource "aws_iam_role_policy_attachment" "eks_worker_node" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "ecr_read" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}
