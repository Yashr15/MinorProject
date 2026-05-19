# ┌──────────────────────────────────────────────────────────┐
# │  terraform.tfvars — Your project-specific values         │
# │                                                          │
# │  Edit these values to match your setup.                  │
# │  These override the defaults in variables.tf             │
# └──────────────────────────────────────────────────────────┘

aws_region   = "ap-south-1"       # Mumbai — your deployment region
project_name = "online-boutique"

# EKS Cluster
cluster_name    = "online-boutique-eks"
cluster_version = "1.30"

# ─── Application Node Group (m7i-flex.large) ────
# Runs the 11 microservices
# m7i-flex.large = 2 vCPU, 8GB RAM (~$0.08/hr in Mumbai)
app_node_instance_type = "m7i-flex.large"
app_node_desired_count = 2     # 2 nodes to start
app_node_min_count     = 1     # Scale down to 1 when idle
app_node_max_count     = 3     # Scale up to 3 under load

# ─── Infrastructure Node Group (c7i-flex.large) ─
# Runs Prometheus, Grafana, and other infra workloads
# c7i-flex.large = 2 vCPU, 4GB RAM (~$0.07/hr in Mumbai)
infra_node_instance_type = "c7i-flex.large"
infra_node_desired_count = 1   # 1 node for monitoring
infra_node_min_count     = 1
infra_node_max_count     = 2

# Network
vpc_cidr = "10.0.0.0/16"
