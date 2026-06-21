# Setup Guide — Step by Step

This guide walks you through setting up the entire project from scratch.

---

## Step 1 — Install Required Tools

Install these on your local machine before starting:

| Tool | Version | Install Command |
|------|---------|----------------|
| AWS CLI | v2+ | `brew install awscli` |
| Terraform | ≥ 1.5 | `brew install terraform` |
| kubectl | latest | `brew install kubectl` |
| Docker | latest | [docker.com/get-docker](https://docs.docker.com/get-docker/) |
| Helm | v3+ | `brew install helm` |
| Git | latest | `brew install git` |

> For Linux, replace `brew` with `apt` or `yum` equivalents.

---

## Step 2 — Configure AWS

### 2.1 Create an IAM User

1. Go to **AWS Console → IAM → Users → Create User**
2. Name: `online-boutique-admin`
3. Attach these policies:
   - `AdministratorAccess` (for dev/learning — in production, use least privilege)
4. Create **Access Key** (CLI type)
5. Save the Access Key ID and Secret

### 2.2 Configure AWS CLI

```bash
aws configure
```

Enter:
- **Access Key ID:** (from step above)
- **Secret Access Key:** (from step above)
- **Region:** `ap-south-1`
- **Output format:** `json`

### 2.3 Verify

```bash
aws sts get-caller-identity
```

You should see your account ID and user ARN.

---

## Step 3 — Set Up Terraform Remote State

This creates an S3 bucket and DynamoDB table so Terraform state is stored securely in the cloud (not on your laptop).

```bash
./scripts/setup-backend.sh
```

This only needs to be run **once per AWS account**.

---

## Step 4 — Deploy Infrastructure + App

### Option A: One-Command Deploy (Recommended)

```bash
./scripts/deploy.sh
```

This single script does everything:
1. Creates VPC, subnets, NAT gateway
2. Creates EKS cluster with node groups
3. Creates ECR repositories for all 11 services
4. Builds all Docker images
5. Pushes images to ECR
6. Deploys to Kubernetes
7. Installs Prometheus + Grafana

**Takes about 15-20 minutes** (EKS cluster creation is the slowest part).

### Option B: Manual Step-by-Step

If you prefer doing it manually:

```bash
# 1. Create infrastructure
cd terraform
terraform init
terraform workspace new dev
terraform plan
terraform apply

# 2. Connect kubectl to EKS
# Run the kubectl_configure command outputted by Terraform, or run:
aws eks update-kubeconfig --region ap-south-1 --name $(terraform output -raw cluster_name)

# 3. Build and push Docker images
cd ..
./scripts/build-push.sh

# 4. Deploy to Kubernetes
kubectl apply -k kubernetes-manifests/

# 5. Install monitoring
./scripts/install-monitoring.sh
```

---

## Step 5 — Access the Application

### Frontend (the e-commerce website)

```bash
kubectl get svc frontend-external
```

Copy the `EXTERNAL-IP` and open it in your browser. It may take 2-3 minutes for the LoadBalancer to get an IP.

### Grafana (monitoring dashboards)

```bash
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
```

Open http://localhost:3000
- **Username:** `admin`
- **Password:** `prom-operator`

### Prometheus (raw metrics)

```bash
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring
```

Open http://localhost:9090

---

## Step 6 — Set Up Jenkins (CI/CD)

Jenkins automates the build → push → deploy cycle so you don't have to run scripts manually.

### 6.1 Install Jenkins

**Option A — Run on a separate EC2 instance (recommended):**

```bash
# Launch an Ubuntu t3.medium EC2 instance, then SSH in and run:
sudo apt update -y

# Install Java 21 (required for Jenkins 2.555+)
sudo apt install -y openjdk-21-jdk

# Add Jenkins 2026 GPG signing key
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null

# Register the stable repository
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list

# Update package lists and install Jenkins
sudo apt update -y
sudo apt install -y jenkins
sudo systemctl enable --now jenkins
```

**Option B — Run locally with Docker:**

```bash
docker run -d -p 8080:8080 -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  --name jenkins jenkins/jenkins:lts
```

### 6.2 Initial Setup

1. Open `http://<jenkins-ip>:8080` (where `<jenkins-ip>` is the public IP of your EC2 instance or `localhost`).
2. Get the initial admin password:
   ```bash
   # EC2:
   sudo cat /var/lib/jenkins/secrets/initialAdminPassword
   # Docker:
   docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
   ```
3. Install **suggested plugins**.
4. Create your admin user.

### 6.3 Install Required Plugins

Go to **Manage Jenkins → Plugins → Available** and install:

| Plugin | Purpose |
|--------|---------|
| **Pipeline** | Run Jenkinsfile pipelines |
| **Docker Pipeline** | Build Docker images in pipeline |
| **Pipeline: AWS Steps** | AWS authentication in pipeline |
| **Git** | Pull code from GitHub |

### 6.4 Install & Configure Docker on Jenkins Server

Jenkins needs Docker to build images and must have group permissions:

```bash
# Install Docker
sudo apt install -y docker.io
sudo systemctl enable --now docker

# Give Jenkins and default Ubuntu users permission to run Docker commands
sudo usermod -aG docker jenkins
sudo usermod -aG docker ubuntu

# Restart Jenkins to apply group membership changes
sudo systemctl restart jenkins
```

### 6.5 Install kubectl on Jenkins Server

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl
```

### 6.6 Install AWS CLI on Jenkins Server

```bash
sudo apt install -y unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf awscliv2.zip aws
```

### 6.7 Configure Credentials in Jenkins

Go to **Manage Jenkins → Credentials → Global → Add Credentials**:

| Credential ID | Type | Value |
|---------------|------|-------|
| `aws-credentials` | AWS Credentials | Your AWS Access Key + Secret Key (from your local `[user2]` profile keys) |
| `aws-account-id` | Secret text | Your 12-digit AWS Account ID (`553136990999`) |

### 6.8 Configure EKS Access for Jenkins (Critical Ritual)

By default, EKS only allows the AWS identity that created the cluster to connect. To authorize Jenkins:

1. **Find Jenkins' AWS Identity:** Find the AWS IAM User or Role ARN that corresponds to the `aws-credentials` configured above.
2. **Update Terraform configuration:** Open `terraform/terraform.tfvars` and set the `jenkins_iam_arn` variable:
   ```hcl
   jenkins_iam_arn = "arn:aws:iam::<YOUR_ACCOUNT_ID>:user/<JENKINS_AWS_USER>"
   ```
3. **Apply the configuration:** Run the following commands in the `terraform/` directory:
   ```bash
   terraform apply
   ```
   *Note: This will add the Access Entry to EKS without replacing or destroying the cluster.*

### 6.9 Create the Pipeline

1. **New Item → Pipeline**
2. Name: `online-boutique`
3. Under **Pipeline**:
   - Definition: **Pipeline script from SCM**
   - SCM: **Git**
   - Repository URL: `https://github.com/Yashr15/MinorProject.git` (or your personal fork)
   - Credentials: **- none -** (since it is a public repository)
   - Branch: `*/main`
   - Script path: `Jenkinsfile`
4. **Save → Build Now**

Jenkins will now automatically build all 11 services, push to ECR, and deploy to EKS.

---

## Tear Down (When Done)

```bash
./scripts/destroy.sh
```

This safely removes everything in reverse order:
1. Deletes K8s deployments
2. Uninstalls monitoring
3. Destroys all Terraform infrastructure (VPC, EKS, ECR, IAM)

---

## Troubleshooting Common Issues

### 1. Terraform State Lock Errors (`Error acquiring the state lock`)
If a deployment fails or is terminated abruptly, the remote state lock might remain active. You will see an error like:
`Error acquiring the state lock... Lock Info: ID: <LOCK_ID>`.

**To fix this:**
Run the unlock command in the `terraform/` directory using the ID from the error message:
```bash
terraform force-unlock <LOCK_ID>
```

### 2. Jenkins Fails to Connect to EKS (`Unauthorized` or Connection Timeout)
- **Unauthorized:** Double check that `jenkins_iam_arn` in `terraform/terraform.tfvars` matches the credentials used by Jenkins, and that you ran `terraform apply`.
- **Connection Timeout:** Ensure that the Jenkins instance IP is allowed by the security groups or is running within the VPC.

### 3. kubectl get nodes returns "Forbidden" or "Unauthorized" for Developer Profile

This occurs when the IAM principal configured in your local `~/.kube/config` is either missing an EKS Access Entry or has had its EKS Access Policy Association removed.

#### Why this happens:
If you provision the cluster, then assign a specific IAM user to `jenkins_iam_arn` in `terraform.tfvars`, Terraform takes management of that user's policy association. If you later clear `jenkins_iam_arn` (setting it to `""`), Terraform destroys the policy association, stripping that IAM user of all EKS permissions. Additionally, if `~/.kube/config` hardcodes the `AWS_PROFILE` environment variable for that user entry, `kubectl` will always run as that profile regardless of your terminal's active profile.

#### How to fix this:

1. **Restore policy association via AWS CLI**:
   Run the following command using an IAM user with AWS Admin permissions (like `terra-user`) to manually associate the EKS admin policy back to your developer/creator user:
   ```bash
   aws eks associate-access-policy \
     --cluster-name online-boutique-eks-dev \
     --principal-arn arn:aws:iam::553136990999:user/terraform-admin \
     --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
     --access-scope type=cluster
   ```

2. **Authorize other developer profiles (Recommended)**:
   Instead of modifying the shared `terraform.tfvars` file, create a local, git-ignored `local.tfvars` file under `terraform/` and declare any developer profiles you want to authorize:
   ```hcl
   additional_admin_arns = [
     "arn:aws:iam::553136990999:user/terraform-admin"
   ]
   ```
   Then apply it:
   ```bash
   terraform apply -var-file="local.tfvars"
   ```

3. **Check/Clean local kubeconfig**:
   If your terminal's active AWS profile is different from the one configured in `~/.kube/config` (or if your kubeconfig hardcodes an `AWS_PROFILE` environment variable for the cluster's exec helper), edit your `~/.kube/config` file to remove the hardcoded profile from the `env` section under the user definition. This allows `kubectl` to automatically use your active CLI profile.
