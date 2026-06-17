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

