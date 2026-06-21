# Project Changelog — Record of Applied Changes

This file records every modification made to the codebase to fix issues during deployment, build processes, and orchestration.

---

## 1. Scripts & Pipeline Configurations

### [scripts/setup-backend.sh](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/scripts/setup-backend.sh)
* **Change:** Added `export AWS_PAGER=""` and redirected check command outputs (`>/dev/null 2>&1`).
* **Why:** In AWS CLI v2, outputs are interactive by default (using `less`), which blocks non-interactive script executions. This also caused the script's `if` conditions to evaluate as failures, triggering a `ResourceInUseException` by trying to recreate the existing DynamoDB lock table.

### [scripts/deploy.sh](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/scripts/deploy.sh)
* **Change 1:** Updated `CLUSTER_NAME` to be retrieved dynamically via `CLUSTER_NAME=$(terraform output -raw cluster_name)` after Terraform apply.
* **Why:** The script was hardcoded to configure kubectl for `online-boutique-eks-dev`, but Terraform creates the cluster as `online-boutique-eks-dev-dev`. Querying this dynamically ensures the script connects to the correct EKS cluster without forcing a destructive cluster rename.
* **Change 2:** Updated the `sed` replacement regex from `image: ${SERVICE}$` to `image:[[:space:]]*([^[:space:]]+/)?${SERVICE}(:[^[:space:]]+)?([[:space:]]+.*)?$`.
* **Why:** The old regex failed to replace the `emailservice` image because of its trailing comment. The new regex is robust and matches local images (with comments) as well as existing ECR registry URLs from previous runs.

### [Jenkinsfile](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/Jenkinsfile)
* **Change:** Updated the environment variable `EKS_CLUSTER` from `online-boutique-eks` to `online-boutique-eks-dev-dev`.
* **Why:** To align the CI/CD pipeline with the actual EKS cluster name provisioned by Terraform.

---

## 2. Dockerfiles & Container Compilations

### [src/paymentservice/Dockerfile](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/src/paymentservice/Dockerfile) & [src/currencyservice/Dockerfile](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/src/currencyservice/Dockerfile)
* **Change:** Changed the base images from `node:22-alpine` to `node:20-alpine` and installed build tools: `apk add --no-cache python3 make g++ gcc`.
* **Why:** The Google Cloud Profiler dependency (`pprof`) compiles native C++ modules. There are no precompiled binaries for Node 22 on Alpine (`musl`), and Node 22's V8 engine has breaking API removals causing compilation to fail. Downgrading to Node 20 (LTS) and providing compilers allows the native module to compile successfully.

### [src/loadgenerator/Dockerfile](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/src/loadgenerator/Dockerfile)
* **Change:** Modified the `ENTRYPOINT` from JSON-array form to shell-wrapped exec form: `ENTRYPOINT ["sh", "-c", "exec locust ..."]`.
* **Why:** JSON-array entrypoints run the binary directly without shell interpretation, passing env variables like `${USERS:-10}` literally to Locust, causing a crash. Wrapping it in `sh -c` forces the shell to expand the environment variables at startup.

---

## 3. Kubernetes Orchestration Manifests

### [kubernetes-manifests/frontend.yaml](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/kubernetes-manifests/frontend.yaml)
* **Change:** Added back the environment variable `SHOPPING_ASSISTANT_SERVICE_ADDR` with a placeholder value (`shoppingassistantservice:8080`).
* **Why:** Although the shopping assistant service was commented out from the manifest files, the Go frontend code still ran a validation check at startup that panicked if this variable was empty.

### [kubernetes-manifests/cartservice.yaml](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/kubernetes-manifests/cartservice.yaml)
* **Change:** Added the environment variable `ASPNETCORE_HTTP_PORTS` set to `"7070"`.
* **Why:** Modern .NET runtimes bind to port `8080` by default. Since the Kubernetes manifest probes and service were looking on port `7070`, Kubelet assumed the container was dead and continuously restarted it. 

---

## 4. Cloud Infrastructure (Terraform)

### [terraform/vpc.tf](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/terraform/vpc.tf)
* **Change:** Updated public and private subnet resource tags to use `local.cluster_name` instead of `var.cluster_name`.
* **Why:** The subnets were tagged with `online-boutique-eks-dev` (derived from the variable default), but the actual EKS cluster was named `online-boutique-eks-dev-dev`. Because of this name mismatch, EKS was unable to auto-discover subnets, leaving the LoadBalancer in `<pending>` status.

---

## 5. Monitoring & Documentation

### [monitoring/prometheus-values.yaml](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/monitoring/prometheus-values.yaml)
* **Change:** Set `grafana.persistence.enabled` to `false` and removed the `prometheusSpec.storageSpec` block.
* **Why:** In EKS 1.30, the legacy in-tree EBS storage provisioner is disabled. Attempting to deploy with persistence enabled caused Grafana and Prometheus to block on pending volume claims (PVCs) since the AWS EBS CSI driver was not installed. Disabling persistence runs them in ephemeral mode, solving the issue immediately.

### [docs/SETUP_GUIDE.md](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/docs/SETUP_GUIDE.md) & [scripts/install-monitoring.sh](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/scripts/install-monitoring.sh)
* **Change:** Corrected the Prometheus service port-forward reference name from `monitoring-kube-prometheus-stack-prometheus` to `monitoring-kube-prometheus-prometheus`.
* **Why:** To match the exact service name deployed by the Helm chart and prevent `NotFound` errors.

### [.gitignore](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/.gitignore)
* **Change:** Added `*.tfplan` and `tfplan`.
* **Why:** To prevent local Terraform plan binaries from being added to Git status and committed to remote repositories.

---

## 6. Terraform State Drift, EKS Import & Autoscaling Implementation

### [terraform/modules/eks/main.tf](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/terraform/modules/eks/main.tf)
* **Change:** Added `bootstrap_self_managed_addons = false` to the EKS cluster definition.
* **Why:** To match the default AWS configuration of the EKS cluster created in the first run, preventing Terraform from trying to destroy and recreate the active cluster.

### [kubernetes-manifests/hpa.yaml](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/kubernetes-manifests/hpa.yaml)
* **Change:** Created a HorizontalPodAutoscaler (HPA) resource `frontend-hpa`.
* **Why:** To automatically scale frontend pods between 1 and 5 replicas based on CPU load.

### [kubernetes-manifests/kustomization.yaml](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/kubernetes-manifests/kustomization.yaml)
* **Change:** Appended `hpa.yaml` to the list of resource paths.
* **Why:** To include the new HPA configuration in the default `kubectl apply` kustomize deploy sequence.

---

## 7. Jenkins CI/CD Setup, EKS Authentication Upgrade & Cluster Reconfiguration

### [terraform/modules/eks/main.tf](file:///c:/Users/Yasha%20Goyal/Documents/test-project/MinorProject/terraform/modules/eks/main.tf)
* **Change:** Added the `access_config` block with `authentication_mode = "API_AND_CONFIG_MAP"` and enabled bootstrap permissions.
* **Why:** To upgrade the EKS cluster from the legacy `CONFIG_MAP` auth mode to the modern Access Entries API, allowing other IAM users/roles (like Jenkins) to authenticate.

### [terraform/eks.tf](file:///c:/Users/Yasha%20Goyal/Documents/test-project/MinorProject/terraform/eks.tf)
* **Change 1:** Removed the duplicate `aws_eks_access_entry.user2` resource.
* **Why:** Since `user2` is the cluster creator and bootstrap admin permissions are enabled, adding it again caused a conflict (`ResourceInUseException`).
* **Change 2:** Corrected the policy ARN format for `default_user` to use the EKS-specific path (`arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy`).
* **Why:** EKS Access Policy associations require cluster-access-policy ARNs rather than standard IAM policy ARNs, which originally caused an `InvalidParameterException`.

### [Jenkinsfile](file:///c:/Users/Yasha%20Goyal/Documents/test-project/MinorProject/Jenkinsfile)
* **Change:** Updated `EKS_CLUSTER` to `online-boutique-eks-dev-dev-dev`.
* **Why:** To align the Jenkins deploy stage with the new cluster name provisioned by Terraform in the workspace.

### [docs/SETUP_GUIDE.md](file:///c:/Users/Yasha%20Goyal/Documents/test-project/MinorProject/docs/SETUP_GUIDE.md)
* **Change:** Merged and refined Step 6 to document Java 21, the 2026 GPG signing keys, Docker daemon group configuration, and AWS CLI + `kubectl` local server setups.
* **Why:** To ensure the central setup documentation is correct, functional, and up-to-date.

---

## 8. Directory Content Hashing & ECR Checking (Incremental Builds & Zero-Downtime Deployments)

### [Jenkinsfile](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/Jenkinsfile)
* **Change 1:** Implemented directory-specific Git commit hashing to tag docker images (`git log -1 --format='%h' -- ${context}`).
* **Change 2:** Added ECR image validation (`aws ecr describe-images`) to dynamically skip building and pushing already existing images.
* **Change 3:** Updated the `Update Manifests` stage to use a robust regular expression: `sed -E -i 's|image:[[:space:]]*([^[:space:]]+/)?${svc}(:[^[:space:]]+)?([[:space:]]+.*)?\$|image: ${ecrImage}|g'`.
* **Why:** To prevent rebuilding and pushing unmodified services on every build, and to fix a critical bug where naive `sed` replacements failed to update image tags in Kubernetes manifest files.

### [scripts/build-push.sh](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/scripts/build-push.sh) & [scripts/deploy.sh](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/scripts/deploy.sh)
* **Change 1:** Configured context directories per service (e.g. `src/cartservice/src` for `cartservice`).
* **Change 2:** Replaced the global commit tag with folder-specific git logs.
* **Change 3:** Integrated `aws ecr describe-images` checks before docker builds.
* **Why:** To enable local developers to run incremental builds, saving bandwidth and computing resources, while ensuring Kubernetes only updates pods of modified services (zero-downtime rolling updates).

### [terraform/eks.tf](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/terraform/eks.tf), [terraform/variables.tf](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/terraform/variables.tf), [terraform/terraform.tfvars](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/terraform/terraform.tfvars) & [terraform/modules/eks/main.tf](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/terraform/modules/eks/main.tf)
* **Change 1:** Introduced the `jenkins_iam_arn` and `additional_admin_arns` variables.
* **Change 2:** Added conditional `aws_eks_access_entry.jenkins` and its corresponding admin access policy association.
* **Change 3:** Created `aws_eks_access_entry.additional` and its policy association to dynamically grant cluster access to developers' local AWS profiles.
* **Change 4:** Disabled `bootstrap_self_managed_addons` to prevent node group destruction on updates.
* **Why:** To authorize multiple developers (like `terra-user`) and Jenkins, resolving the "Unauthorized" `kubectl` connection errors, and preventing EKS cluster control plane downtime.

### [docs/SETUP_GUIDE.md](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/docs/SETUP_GUIDE.md)
* **Change:** Documented Step 6.8 "Configure EKS Access for Jenkins" and added state unlocking troubleshooting steps.
* **Why:** To establish a clear, repeatable post-clone EKS setup ritual for developers and CI/CD pipelines.

---

## 9. Multi-Developer Portability & Clean Infrastructure Integration

### [kubernetes-manifests/*.yaml](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/kubernetes-manifests/)
* **Change:** Replaced all hardcoded AWS ECR registry prefixes (`553136990999.dkr.ecr.ap-south-1.amazonaws.com/`) with generic, relative container image names (e.g. `image: frontend`).
* **Why:** To make the manifests portable across multiple AWS accounts, allowing deploy scripts to dynamically inject the active account's ECR URL.

### [terraform/providers.tf](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/terraform/providers.tf) & [scripts/deploy.sh](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/scripts/deploy.sh)
* **Change 1:** Removed the hardcoded `bucket` key from the S3 backend block in `providers.tf`.
* **Change 2:** Updated `deploy.sh` to initialize Terraform dynamically using the active caller account: `terraform init -input=false -backend-config="bucket=online-boutique-terraform-state-${AWS_ACCOUNT_ID}"`.
* **Why:** Decoupled the Terraform backend state bucket, enabling any developer to deploy to their own AWS account without modifying tracked files.

### [terraform/terraform.tfvars](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/terraform/terraform.tfvars) & [.gitignore](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/.gitignore)
* **Change 1:** Reset `additional_admin_arns` to `[]` in the committed variables file.
* **Change 2:** Added `*local.tfvars` and `*secret.tfvars` patterns to `.gitignore`.
* **Why:** To keep personal IAM user ARNs out of tracked repository commits, allowing developers to create custom local variables files that are ignored by Git.

### [kubernetes-manifests/hpa.yaml](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/kubernetes-manifests/hpa.yaml)
* **Change:** Updated CPU target average utilization threshold from `10%` to `50%`.
* **Why:** To stop pod thrashing (repeatedly creating and destroying pods) under idle or minimal load conditions.

### [Jenkinsfile](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/Jenkinsfile)
* **Change 1:** Configured the pipeline to dynamically compute the `EKS_CLUSTER` name using the workspace environment branch prefix instead of hardcoding `dev-dev-dev`.
* **Change 2:** Implemented aggressive Docker cleanup rules (`docker container prune`, `image prune -a`, `builder prune -a`) in the `always` post block to reclaim build agent disk space.

---

## 10. EKS Access Recovery, Kubeconfig Environment Clean-up & Jenkins Pipeline Resiliency

### [terraform/eks.tf](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/terraform/eks.tf) & EKS Access Policies
* **Change:** Restored EKS Access Policy associations for the `terraform-admin` principal. Added EKS Access Entry and EKS Access Policy Association for the default CLI terminal profile (`terra-user`).
* **Why:** Clearing `jenkins_iam_arn` to `""` in `terraform.tfvars` caused Terraform to destroy the policy association resource mapping `AmazonEKSClusterAdminPolicy` to `terraform-admin`. This stripped `terraform-admin` of EKS permissions, resulting in `Forbidden` errors. Manually restoring it via AWS CLI and adding the default CLI user ensured both identities have cluster administrator access.

### [~/.kube/config](file:///Users/yash/.kube/config)
* **Change:** Removed the hardcoded `AWS_PROFILE` environment variable override (`value: user2`) from the EKS cluster user configuration.
* **Why:** The local kubeconfig file forced `kubectl` to authenticate as `terraform-admin` (`user2`) regardless of the terminal's active AWS profile. Stripping the environment block allows `kubectl` to dynamically fall back to the terminal's active profile (`terra-user`), preventing permission mismatches.

### [Jenkinsfile](file:///Users/yash/Desktop/desktop%20files/minorProject/MinorProject/Jenkinsfile)
* **Change:** Injected an active check for the `terraform` command. If the Terraform CLI is not found on the Jenkins server agent, the pipeline automatically downloads the Linux binary for Terraform `1.9.0`, unzips it (using Python's `zipfile` module as a fail-safe fallback), and registers it on the execution path.
* **Why:** The self-hosted Jenkins agent EC2 instance (`jenkin-yuv`) did not have the Terraform CLI pre-installed, causing the deployment stage to fail with `terraform: not found`. Adding dynamic installation ensures pipeline self-containment and resiliency.
