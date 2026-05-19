# Infrastructure Overview

This document explains what infrastructure the project creates, how many servers run, and the estimated cost.

---

## Architecture Diagram

```
┌─────────────────────────────── AWS Cloud (ap-south-1 / Mumbai) ────────────────────────────────┐
│                                                                                                 │
│  ┌──────────────────────────────── VPC: 10.0.0.0/16 ──────────────────────────────────────┐     │
│  │                                                                                        │     │
│  │   Public Subnets (2 AZs)                    Private Subnets (2 AZs)                    │     │
│  │   ┌──────────────────┐                      ┌──────────────────────────────────────┐   │     │
│  │   │ 10.0.0.0/24 (AZ1)│                      │ 10.0.10.0/24 (AZ1)                  │   │     │
│  │   │ 10.0.1.0/24 (AZ2)│                      │ 10.0.11.0/24 (AZ2)                  │   │     │
│  │   │                  │                      │                                      │   │     │
│  │   │  ┌────────────┐  │    ┌──────────┐      │  ┌─────────────────────────────────┐ │   │     │
│  │   │  │ Internet   │  │    │   NAT    │      │  │  EKS Cluster                    │ │   │     │
│  │   │  │ Gateway    │  │    │ Gateway  │      │  │                                 │ │   │     │
│  │   │  └─────┬──────┘  │    └────┬─────┘      │  │  App Nodes (2-3 instances)      │ │   │     │
│  │   │        │         │         │            │  │  ┌───────┐ ┌───────┐ ┌───────┐  │ │   │     │
│  │   │  ┌─────▼──────┐  │         │            │  │  │Node 1 │ │Node 2 │ │Node 3 │  │ │   │     │
│  │   │  │ AWS ELB    │  │         │            │  │  │(m7i)  │ │(m7i)  │ │(m7i)  │  │ │   │     │
│  │   │  │ LoadBalancr│──┼─────────┼────────────┼──┼─▶│       │ │       │ │       │  │ │   │     │
│  │   │  └────────────┘  │         │            │  │  └───────┘ └───────┘ └───────┘  │ │   │     │
│  │   │                  │         │            │  │                                 │ │   │     │
│  │   └──────────────────┘         │            │  │  Infra Nodes (1-2 instances)    │ │   │     │
│  │                                │            │  │  ┌───────┐ ┌───────┐            │ │   │     │
│  │                                │            │  │  │Node 1 │ │Node 2 │            │ │   │     │
│  │                                │            │  │  │(c7i)  │ │(c7i)  │            │ │   │     │
│  │                                │            │  │  │Monit. │ │Monit. │            │ │   │     │
│  │                                │            │  │  └───────┘ └───────┘            │ │   │     │
│  │                                │            │  └─────────────────────────────────┘ │   │     │
│  │                                │            └──────────────────────────────────────┘   │     │
│  └────────────────────────────────┴──────────────────────────────────────────────────────┘     │
│                                                                                                 │
│  ┌─────────────────┐                                                                            │
│  │  ECR (11 repos) │  ← Docker images stored here                                              │
│  └─────────────────┘                                                                            │
└─────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Servers / Instances

### EKS Control Plane
- **Managed by AWS** — you don't see or manage these servers
- AWS runs the Kubernetes API server, etcd, scheduler, etc.
- **Cost:** $0.10/hr ($73/month)

### Application Node Group

These run the 11 microservice pods.

| Setting | Value |
|---------|-------|
| **Instance type** | `m7i-flex.large` |
| **vCPUs** | 2 per node |
| **RAM** | 8 GB per node |
| **Min nodes** | 1 |
| **Desired nodes** | 2 |
| **Max nodes** | 3 |
| **Cost per node** | ~$0.08/hr (~$58/month) |
| **Placed in** | Private subnets |

**Why m7i-flex.large?** — General-purpose instance with enough memory for the Java (adservice) and .NET (cartservice) workloads that are heavier than the Go/Python services.

### Infrastructure Node Group

These run monitoring (Prometheus + Grafana).

| Setting | Value |
|---------|-------|
| **Instance type** | `c7i-flex.large` |
| **vCPUs** | 2 per node |
| **RAM** | 4 GB per node |
| **Min nodes** | 1 |
| **Desired nodes** | 1 |
| **Max nodes** | 2 |
| **Cost per node** | ~$0.07/hr (~$51/month) |
| **Placed in** | Private subnets |
| **Taint** | `dedicated=infrastructure:NoSchedule` |

**Why separated?** — The taint prevents app pods from landing on infra nodes. This ensures monitoring always has resources and doesn't compete with microservices.

**Why c7i-flex?** — Compute-optimized. Prometheus needs CPU for scraping and querying metrics, not memory.

---

## What Gets Created

When you run `terraform apply`, these AWS resources are created:

### Networking (VPC)
| Resource | Count | Purpose |
|----------|-------|---------|
| VPC | 1 | Isolated network for the entire project |
| Public Subnets | 2 | Load Balancer sits here (internet-facing) |
| Private Subnets | 2 | Worker nodes run here (not directly exposed) |
| Internet Gateway | 1 | Lets public subnets reach the internet |
| NAT Gateway | 1 | Lets private nodes pull Docker images from ECR |
| Elastic IP | 1 | Static IP for the NAT Gateway |
| Route Tables | 2 | Public routes → IGW, Private routes → NAT |

### Compute (EKS)
| Resource | Count | Purpose |
|----------|-------|---------|
| EKS Cluster | 1 | Managed Kubernetes control plane |
| App Node Group | 1 | 2-3 nodes running microservices |
| Infra Node Group | 1 | 1-2 nodes running monitoring |

### Container Registry (ECR)
| Resource | Count | Purpose |
|----------|-------|---------|
| ECR Repositories | 11 | One per microservice, stores Docker images |
| Lifecycle Policies | 11 | Auto-delete old untagged images |

### Security (IAM)
| Resource | Count | Purpose |
|----------|-------|---------|
| EKS Cluster Role | 1 | Lets EKS manage AWS resources |
| Node Group Role | 1 | Lets nodes join cluster + pull from ECR |
| Policy Attachments | 4 | EKSClusterPolicy, WorkerNode, CNI, ECR Read |

**Total AWS resources created: ~30**

---

## Estimated Monthly Cost

| Resource | Cost/Month |
|----------|-----------|
| EKS Control Plane | $73 |
| App Nodes (2× m7i-flex.large) | $116 |
| Infra Node (1× c7i-flex.large) | $51 |
| NAT Gateway | $32 + data transfer |
| Elastic IP | $3.65 |
| ECR Storage | ~$1-5 (depends on image sizes) |
| ELB (LoadBalancer) | ~$16 + data transfer |
| **Total (estimated)** | **~$290-300/month** |

> **Tip:** To save costs during development, scale app nodes to 1 and destroy infrastructure when not in use with `./scripts/destroy.sh`.

---

## What Runs on Each Node

### App Nodes (each m7i-flex.large runs some of these):

| Pod | CPU Request | Memory Request |
|-----|------------|----------------|
| frontend | 100m | 64Mi |
| cartservice | 200m | 64Mi |
| productcatalogservice | 100m | 64Mi |
| currencyservice | 100m | 64Mi |
| paymentservice | 100m | 64Mi |
| shippingservice | 100m | 64Mi |
| emailservice | 100m | 64Mi |
| checkoutservice | 100m | 64Mi |
| recommendationservice | 100m | 220Mi |
| adservice | 200m | 180Mi |
| loadgenerator | 300m | 256Mi |
| redis-cart | 70m | 200Mi |
| **Total** | **1570m** | **1368Mi** |

Each m7i-flex.large has 2000m CPU and 8Gi RAM — so 2 nodes comfortably fit all pods with room to spare for scaling.

### Infra Nodes (c7i-flex.large):

| Pod | CPU Request | Memory Request |
|-----|------------|----------------|
| Prometheus | 200m | 512Mi |
| Grafana | 100m | 128Mi |
| Alertmanager | 50m | 64Mi |
| Node Exporter | 50m | 32Mi |
| Kube State Metrics | ~100m | ~128Mi |
| **Total** | **~500m** | **~864Mi** |

Fits easily on a single c7i-flex.large (2000m CPU, 4Gi RAM).

---

## Auto-Scaling Behavior

### Node-Level Auto-Scaling
- EKS Managed Node Groups automatically add/remove EC2 instances
- If pods can't be scheduled (not enough CPU/memory), a new node is added
- If nodes are underutilized, they're removed
- App nodes: scales between 1 and 3
- Infra nodes: scales between 1 and 2

### Pod-Level Self-Healing
- Every pod has **liveness probes** — if a pod becomes unhealthy, Kubernetes restarts it
- Every pod has **readiness probes** — if a pod isn't ready, traffic stops going to it
- If a node dies, all pods on it are rescheduled to healthy nodes

---

## Multi-Environment Support

The project supports multiple environments using Terraform workspaces:

```bash
./scripts/deploy.sh dev       # Creates: online-boutique-eks-dev
./scripts/deploy.sh staging   # Creates: online-boutique-eks-staging
./scripts/deploy.sh prod      # Creates: online-boutique-eks-prod
```

Each environment gets its own:
- EKS cluster
- VPC and subnets
- ECR repositories
- IAM roles
- Terraform state file (in S3)

No resource name collisions between environments.
