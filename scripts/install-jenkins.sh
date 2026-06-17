#!/bin/bash
# ═══════════════════════════════════════════════════════════
# install-jenkins.sh — Automated script for remote EC2 server
# ═══════════════════════════════════════════════════════════

set -euo pipefail

echo "================================================="
echo " Installing Jenkins and CI/CD Prerequisites"
echo "================================================="

# 1. Update Package Lists
sudo apt update -y

# 2. Install Java 21
sudo apt install -y openjdk-21-jdk

# 3. Add Jenkins Stable Key & Repository (2026 Update)
sudo mkdir -p /usr/share/keyrings
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

# Update and Install Jenkins
sudo apt update -y
sudo apt install -y jenkins
sudo systemctl enable --now jenkins

# 4. Install Docker
sudo apt install -y docker.io
sudo systemctl enable --now docker

# 5. Set Group Permissions for Docker
sudo usermod -aG docker jenkins
sudo usermod -aG docker ubuntu

# 6. Install AWS CLI
sudo apt install -y unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf awscliv2.zip aws

# 7. Install Kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# 8. Restart Jenkins to Apply Permissions
sudo systemctl restart jenkins

echo "================================================="
echo " Installation Complete!"
echo " Jenkins Initial Admin Password:"
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
echo "================================================="
