# Online Boutique — Microservices on AWS

A cloud-native e-commerce app with **11 microservices** running on **AWS EKS**.

Built with **Terraform** for infrastructure, **Jenkins** for CI/CD, and **Prometheus + Grafana** for monitoring.

---

## Architecture

```
                        Internet
                           │
                      LoadBalancer (AWS ELB)
                           │
                        Frontend (Go)
                           │
          ┌────────────────┼────────────────┐
          │                │                │
      Checkout        Product Catalog     Cart ──→ Redis
          │
    ┌─────┼──────┬─────────┬──────────┐
    │     │      │         │          │
  Email Payment Shipping Currency    Ad
```

All services talk to each other using **gRPC** and are discovered via **Kubernetes DNS**.

---

## Services

| Service | Language | Port |
|---------|----------|------|
| frontend | Go | 8080 |
| cartservice | C# | 7070 |
| productcatalogservice | Go | 3550 |
| currencyservice | C++ | 7000 |
| paymentservice | Node.js | 50051 |
| shippingservice | Go | 50051 |
| emailservice | Python | 8080 |
| checkoutservice | Go | 5050 |
| recommendationservice | Python | 8080 |
| adservice | Java | 9555 |
| loadgenerator | Python | — |

---

## Project Structure

```
├── src/                      # Source code + Dockerfiles for all 11 services
├── terraform/                # AWS infrastructure (VPC, EKS, ECR, IAM)
├── kubernetes-manifests/     # K8s deployment + service YAMLs
├── monitoring/               # Prometheus + Grafana config
├── scripts/                  # Automation scripts
├── docs/                     # Setup guide + infrastructure details
├── Jenkinsfile               # CI/CD pipeline
└── docker-compose.yml        # Run locally
```

## Infrastructure at a Glance

| Resource | Type | Count |
|----------|------|-------|
| App Nodes | m7i-flex.large (2 vCPU, 8GB) | 2 (scales 1→3) |
| Infra Nodes | c7i-flex.large (2 vCPU, 4GB) | 1 (scales 1→2) |
| VPC | 10.0.0.0/16 | 1 |
| Subnets | Public + Private | 4 (2 AZs) |
| ECR Repos | One per service | 11 |
| Load Balancer | AWS ELB | 1 |

**Estimated cost:** ~$290/month (destroy when not in use to save money)

> For full details on servers, pod placement, and costs — see [docs/INFRASTRUCTURE.md](docs/INFRASTRUCTURE.md)

---

## How to Deploy

### Prerequisites

- AWS CLI (configured with `aws configure`)
- Terraform ≥ 1.5
- kubectl
- Docker
- Helm

> **First time?** Follow the complete [docs/SETUP_GUIDE.md](docs/SETUP_GUIDE.md) — covers AWS account config, Jenkins setup, credentials, and everything else.

### Step 1 — Set up Terraform remote state (one-time)

```bash
./scripts/setup-backend.sh
```

### Step 2 — Deploy everything

```bash
./scripts/deploy.sh
```

This single command will:
1. Create all AWS infrastructure (VPC, EKS, ECR, IAM)
2. Build all 11 Docker images
3. Push them to ECR
4. Deploy to EKS
5. Install Prometheus + Grafana

### Step 3 — Open the app

```bash
kubectl get svc frontend-external
```

Open the `EXTERNAL-IP` in your browser.

### Step 4 — View Grafana dashboards

```bash
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
```

Open http://localhost:3000 — login with `admin` / `prom-operator`

---

## Key Features

- **Auto-Scaling** — EKS node groups scale from 1 to 3 nodes based on demand
- **Auto-Healing** — every service has health checks; crashed pods restart automatically
- **Infrastructure as Code** — 100% Terraform, nothing created manually
- **CI/CD** — Jenkins builds, pushes, and deploys automatically
- **Monitoring** — Prometheus collects metrics, Grafana visualizes them
- **Multi-Environment** — Terraform workspaces support dev / staging / prod
- **Security** — private subnets for nodes, IAM least privilege, ECR vulnerability scanning

---

## Other Commands

| Command | What it does |
|---------|-------------|
| `./scripts/build-push.sh` | Rebuild and push Docker images only |
| `./scripts/build-push.sh frontend` | Rebuild a specific service |
| `./scripts/install-monitoring.sh` | Install monitoring separately |
| `./scripts/destroy.sh` | Tear down everything |
| `docker compose up` | Run all services locally |
| `kubectl apply -k kubernetes-manifests/` | Deploy to K8s manually |

