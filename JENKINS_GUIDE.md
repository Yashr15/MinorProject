# Jenkins CI/CD Setup & Deployment Guide

This document preserves the step-by-step commands and configurations executed to set up Jenkins on a dedicated Ubuntu EC2 instance (`t3.medium`) and configure the CI/CD pipeline to deploy the Online Boutique microservices to AWS EKS.

---

## 1. Remote Server Setup (Ubuntu EC2 Instance)

These commands were run on the remote EC2 instance after connecting via SSH:

### A. Update Packages & Install Java 21
```bash
sudo apt update -y
sudo apt install -y openjdk-21-jdk
```

### B. Add Jenkins 2026 Signing Key & Repository (Stable Release)
```bash
# Download GPG key (2026 update)
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null

# Register the stable repository
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list

# Update package lists and install Jenkins
sudo apt update -y
sudo apt install -y jenkins
sudo systemctl enable --now jenkins
```

### C. Install Docker & Set Permissions
```bash
sudo apt install -y docker.io -y
sudo systemctl enable --now docker

# Grant Jenkins and default Ubuntu users permission to run Docker commands
sudo usermod -aG docker jenkins
sudo usermod -aG docker ubuntu

# Restart Jenkins to apply group membership changes
sudo systemctl restart jenkins
```

### D. Install AWS CLI & Kubectl
```bash
# Install AWS CLI
sudo apt install -y unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf awscliv2.zip aws

# Install Kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl
```

### E. Get Initial Admin Password
```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

---

## 2. Jenkins Web UI Configuration

### A. Required Plugins
Go to **Manage Jenkins** → **Plugins** → **Available plugins** and install:
* **`Pipeline: AWS Steps`** (Adds credentials integration for AWS commands)
* **`Docker Pipeline`** (Allows building and pushing Docker images)

### B. Credentials Setup
Go to **Manage Jenkins** → **Credentials** → **System** → **Global credentials (unrestricted)** → **Add Credentials**:

1. **`aws-account-id`** (Type: *Secret text*)
   * **Secret:** `553136990999`
   * **ID:** `aws-account-id`
2. **`aws-credentials`** (Type: *AWS Credentials*)
   * **ID:** `aws-credentials`
   * **Access Key ID:** `[Your AWS Access Key ID from user2]`
   * **Secret Access Key:** `[Your AWS Secret Access Key from user2]`

### C. Create Pipeline
1. Click **New Item** → Select **Pipeline**.
2. **Name:** `online-boutique`
3. Scroll to **Pipeline** section:
   * **Definition:** `Pipeline script from SCM`
   * **SCM:** `Git`
   * **Repository URL:** `https://github.com/Yashr15/MinorProject.git`
   * **Credentials:** `- none -` (as the repository is public)
   * **Branch Specifier:** `*/main`
   * **Script Path:** `Jenkinsfile`
4. Click **Save** and trigger with **Build Now**.

---

## 3. Infrastructure Configuration Changes

### A. EKS Access Configuration (`terraform/modules/eks/main.tf`)
Added EKS access entries mode:
```hcl
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
```

### B. Terraform Execution Profile & Workspace
```powershell
cd terraform
terraform workspace select dev
terraform apply -var="environment=dev" -var="cluster_name=online-boutique-eks-dev-dev" -auto-approve
```
