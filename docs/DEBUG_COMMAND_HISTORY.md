# Debugging and Git Commands History

This document lists every command executed during the troubleshooting, deployment, and git workflow processes, along with the reasoning behind each command and the findings it produced.

---

## Part 1: Troubleshooting Pod Crashes and Startup Failures

### 1. `kubectl get pods`
* **Why:** The deployment script timed out waiting for the `frontend` pod to roll out. I used this command to check the current status of all pods.
* **What I was looking for:** Which pods were failing, and what their statuses were (e.g., `CrashLoopBackOff`, `ImagePullBackOff`, `Pending`).
* **Findings:** 
  * `emailservice` was in `ImagePullBackOff`
  * `cartservice`, `frontend`, and `loadgenerator` were in `CrashLoopBackOff`

### 2. `kubectl describe pod emailservice-c866ffb84-2tqqt`
* **Why:** To investigate why the `emailservice` pod could not pull its image.
* **What I was looking for:** The exact container image reference and the error events emitted by the Kubernetes kubelet.
* **Findings:** The image field was set to the local name `emailservice` instead of the AWS ECR registry path. This revealed that the regex replacement in the `deploy.sh` script had skipped this file.

### 3. `kubectl logs -l app=cartservice --tail=50`
* **Why:** To investigate why the `cartservice` pod was crash-looping.
* **What I was looking for:** Application-level crash logs or start logs from the C# runtime.
* **Findings:** The application logged that it started listening on `http://[::]:8080`, but the Kubernetes readiness/liveness probes were querying port `7070`. Because Kubelet couldn't reach it, it repeatedly restarted the container.

### 4. `kubectl logs -l app=frontend --tail=50`
* **Why:** To investigate why the `frontend` pod was crash-looping.
* **What I was looking for:** Go runtime panics or exit codes in the logs.
* **Findings:** The pod panicked with: `panic: environment variable "SHOPPING_ASSISTANT_SERVICE_ADDR" not set`, indicating a missing configuration variable in `frontend.yaml`.

### 5. `kubectl logs -l app=loadgenerator --tail=50`
* **Why:** To investigate why the `loadgenerator` pod was crash-looping.
* **What I was looking for:** Locust framework startup errors.
* **Findings:** It failed with: `locust: error: argument -u/--users: invalid int value: '${USERS:-10}'`. This showed that the Dockerfile's JSON-array `ENTRYPOINT` was not expanding shell environment variables.

---

## Part 2: Troubleshooting Load Balancer and Storage Issues

### 6. `kubectl describe svc frontend-external`
* **Why:** The frontend service was created, but its `EXTERNAL-IP` remained `<pending>` forever.
* **What I was looking for:** Events from the AWS Service Controller trying to allocate the Load Balancer (ELB).
* **Findings:** The event log showed: `SyncLoadBalancerFailed ... could not find any suitable subnets for creating the ELB`. This meant the AWS subnets were missing the tag identifying them as part of the EKS cluster.

### 7. `kubectl get storageclass`
* **Why:** The Prometheus and Grafana Helm install failed waiting for PersistentVolumeClaims (PVCs) to bind.
* **What I was looking for:** The storage class provisioner configured in the cluster.
* **Findings:** The default storage class was `gp2` using `kubernetes.io/aws-ebs` (the legacy in-tree driver), which is disabled/deprecated in EKS 1.30.

### 8. `kubectl get pods -n kube-system`
* **Why:** To verify if the EKS cluster had the modern EBS CSI driver installed to handle dynamic EBS provisioning.
* **What I was looking for:** `ebs-csi-controller` pods.
* **Findings:** Only standard kube-proxy, aws-node, and coredns pods were present; the EBS CSI driver was missing from the cluster.

---

## Part 3: Applying Fixes and Verifying Services

### 9. `terraform apply -var="environment=dev" -var="cluster_name=online-boutique-eks-dev" -auto-approve`
* **Why:** After correcting the subnet tags in `vpc.tf` to use `local.cluster_name` (so it matched the actual cluster name `online-boutique-eks-dev-dev`), I ran this command to update the AWS subnet resources immediately.
* **What I was looking for:** Successful update of the 4 subnets in AWS.
* **Findings:** Applied successfully and instantly resolved the Load Balancer pending issue.

### 10. `kubectl get svc frontend-external`
* **Why:** To check if the Load Balancer public DNS endpoint was successfully generated after applying the tag changes.
* **What I was looking for:** The ELB hostname under the `EXTERNAL-IP` column.
* **Findings:** Successfully generated: `a617201a91ce04833b435441aa100a91-1380969686.ap-south-1.elb.amazonaws.com`.

### 11. `kubectl rollout restart deployment/loadgenerator`
* **Why:** To force EKS to pull the newly built `loadgenerator` Docker image with the fixed shell-expansion entrypoint.
* **What I was looking for:** EKS creating a new pod and terminating the old, failing one.
* **Findings:** The new pod successfully launched and remained `Running`.

### 12. `helm uninstall monitoring -n monitoring`
* **Why:** To clear the half-failed Helm release for Prometheus/Grafana before reinstalling it with persistence disabled.
* **What I was looking for:** A clean state in the `monitoring` namespace.
* **Findings:** Successfully uninstalled.

### 13. `kubectl get pods -n monitoring`
* **Why:** To check if the Prometheus and Grafana pods started up correctly without waiting on EBS volumes.
* **What I was looking for:** All monitoring pods in `Running` status.
* **Findings:** All pods reached the `Running` state and are fully healthy.

### 14. `kubectl get svc -n monitoring`
* **Why:** The command `kubectl port-forward svc/monitoring-kube-prometheus-stack-prometheus` failed with `services not found`. I ran this to find the actual service name.
* **What I was looking for:** The correct Prometheus service service name.
* **Findings:** The service is named `monitoring-kube-prometheus-prometheus` (without the word `stack`).

---

## Part 4: Git Version Control and Pushing to GitHub

### 15. `git status`
* **Why:** To see which files had local modifications before staging them for a commit.
* **What I was looking for:** A list of modified and untracked files.
* **Findings:** All HCL, YAML manifests, and Dockerfiles were correctly tracked as modified. A temporary `terraform/tfplan` file was untracked (which I subsequently added to `.gitignore` and deleted).

### 16. `git remote -v`
* **Why:** To confirm the remote GitHub repository URL we were pushing to.
* **What I was looking for:** The fetch and push URLs for `origin`.
* **Findings:** Set to `https://github.com/Yashr15/MinorProject.git`.

### 17. `git add .`
* **Why:** To stage all modified files (including `.gitignore` updates) for the commit.

### 18. `git commit -m "Fix backend script, EKS cluster name mismatch, Node 22 build issues, and monitoring persistence"`
* **Why:** To create a local commit recording all the fixes applied during this session.

### 19. `git push origin main` (First Attempt)
* **Why:** To upload the local commit to GitHub.
* **Findings:** Rejected because the remote repository had newer changes (commit `6c37caa`) that we did not have locally.

### 20. `git pull --rebase origin main` (Attempted & Aborted)
* **Why:** To fetch the remote changes and rebase our local commit on top of them.
* **Findings:** The command failed due to conflicts in the Dockerfiles (remote had also changed node version to 20). I aborted it via `git rebase --abort` to check the differences cleanly.

### 21. `git diff main..origin/main`
* **Why:** To see what exactly was in the remote commit `6c37caa` before merging it.
* **Findings:** Discovered the remote commit had also set the Terraform backend S3 bucket to a different AWS account (`871148650925`), which would break the user's workspace if we blindly merged.

### 22. `git merge origin/main`
* **Why:** To perform a standard merge so we could resolve conflicts and keep our correct S3 bucket configuration.
* **Findings:** Auto-merging failed with conflicts in `currencyservice/Dockerfile` and `paymentservice/Dockerfile`.

### 23. `git add src/currencyservice/Dockerfile src/paymentservice/Dockerfile terraform/providers.tf`
* **Why:** After resolving conflicts in the Dockerfiles and correcting the S3 bucket to `553136990999` in `providers.tf`, this staged the resolved files.

### 24. `git commit -m "Merge remote-tracking branch 'origin/main' and resolve conflicts"`
* **Why:** To conclude the merge conflict resolution and finalize the merge commit.

### 25. `git push origin main` (Second Attempt)
* **Why:** To push both the local fixes and the merge commit to GitHub.
* **Findings:** Push succeeded.

---

## Part 5: Handling IDE Crashes, State Drift, and Implementing Autoscaling

When the IDE crashed during the initial deployment run, it abruptly terminated the execution of the Terraform provisioning script. This created a split-brain state (also known as state drift or state mismatch) between what was deployed in AWS and what was recorded in the local Terraform state file, leading to multiple deployment blocker conflicts.

### 26. `ps aux | grep -E 'terraform|deploy.sh' | grep -v grep`
* **Why:** The IDE crashed mid-deployment. I ran this to check if the deployment script or Terraform processes were still running in the background.
* **Explanation:** When the IDE crashed, there was a risk that the underlying shell process executing `deploy.sh` or `terraform` was still running. If it was, running another deploy script would create resource collisions and database write contentions. 
* **Findings:** No matching processes were found, confirming the processes terminated during the crash.

### 27. `terraform workspace show`
* **Why:** To verify which environment/workspace (e.g., `dev`) was active in Terraform before troubleshooting the state.
* **Explanation:** Terraform manages isolated state files for each environment (e.g., `dev`, `staging`, `prod`) using workspaces. We needed to confirm we were debugging the correct workspace so that any unlock or import actions were executed against the active target state.
* **Findings:** The active workspace was confirmed to be `dev`.

### 28. `terraform force-unlock 66205517-34bc-37b9-d7cc-1c21ad77be2a`
* **Why:** Because the Terraform process crashed mid-deployment, it left a dangling lock in DynamoDB. Running this command released the lock.
* **Explanation:** Terraform obtains a write lock (using the DynamoDB table `online-boutique-terraform-lock`) whenever an apply begins, preventing concurrent modifications. Because the crash was sudden, the process exited without running the clean-up routines to release the lock, blocking all future runs with a `ConditionalCheckFailedException`.
* **Findings:** The lock was successfully released, allowing the backend state to be read again.

### 29. `aws ec2 describe-route-tables --filters "Name=vpc-id,Values=vpc-09fb38255317cd8da" --region ap-south-1`
* **Why:** The subsequent deploy failed with subnet route table association conflict errors. I used this to inspect the exact associations in AWS.
* **Explanation:** The error log indicated that the private subnets could not be associated with the new route table because they were already associated with another one. Describing all route tables in the VPC revealed that the first crashed run had created a private route table (`rtb-03cf7e9ca5f95aadb`) and associated the subnets with it, but because the state file was never saved, the current state file had no record of this route table and had created a second one (`rtb-0b036faf5d851219b`).
* **Findings:** Identified the conflicting route table (`rtb-03cf7e9ca5f95aadb`) and its specific association IDs (`rtbassoc-0f1c7e6932eec4188` and `rtbassoc-0ae0bedef37a85641`).

### 30. `aws eks describe-cluster --name online-boutique-eks-dev-dev --region ap-south-1`
* **Why:** The subsequent deploy failed with `ResourceInUseException` because the EKS cluster already existed in AWS but was missing from the state. I ran this to check the cluster's current configuration and state.
* **Explanation:** Just like the route table, the EKS cluster had been created in AWS but was never recorded in the Terraform state file. Because EKS cluster names must be unique within an AWS account and region, Terraform's attempt to create a new cluster with the same name was rejected by AWS.
* **Findings:** Confirmed the cluster existed in AWS and was in the `CREATING` state, meaning it was provisioned during the crashed run and was still finishing its control plane setup.

### 31. `aws ec2 disassociate-route-table --association-id rtbassoc-0f1c7e6932eec4188 --region ap-south-1` (and `rtbassoc-0ae0bedef37a85641`)
* **Why:** To break the associations between the private subnets and the old, untracked route table in AWS.
* **Explanation:** You cannot delete or change associations of subnets directly while they have a custom route table association. By disassociating them, they default back to the main VPC route table, freeing them to be associated with the new route table tracked in the Terraform state.
* **Findings:** Successfully broke the network locks on the subnets.

### 32. `aws ec2 delete-route-table --route-table-id rtb-03cf7e9ca5f95aadb --region ap-south-1`
* **Why:** To delete the orphaned, untracked private route table in AWS.
* **Explanation:** Leaving the old private route table in AWS would lead to clean-up failures when tearing down the infrastructure and clutter the AWS Console with unused resources.
* **Findings:** Old route table successfully destroyed.

### 33. `terraform import -var="environment=dev" -var="cluster_name=online-boutique-eks-dev" module.eks.aws_eks_cluster.this online-boutique-eks-dev-dev`
* **Why:** To import the EKS cluster from AWS into the current Terraform state file.
* **Explanation:** By importing the resource, Terraform downloads its configuration from AWS and writes it directly to the state file. This syncs the state file with AWS so that the next time `terraform apply` runs, it knows the cluster already exists and skips the creation step, moving directly to node group creation.
* **Findings:** Import completed successfully.
* *Note: To prevent Terraform from destroying and replacing the imported EKS cluster, we added `bootstrap_self_managed_addons = false` to the configuration inside `terraform/modules/eks/main.tf` to match the configuration EKS automatically created in AWS.*

---

## Part 6: Deploying the Metrics Server and Setting up the Autoscaling Simulation

Once the Terraform state was synced, the deployment script ran successfully and exposed the application. To implement and test Horizontal Pod Autoscaling (HPA), we followed a systematic sequence of commands.

### 34. `kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml`
* **Why:** To install the Kubernetes Metrics Server in the EKS cluster.
* **Explanation:** An HPA scales pods based on resource metrics (like CPU and Memory usage). However, EKS clusters do not have a resource metrics collector installed by default. Running `kubectl top` or HPA without this server returns an `error: Metrics API not available` error.
* **Findings:** Deployed the collector daemon to the `kube-system` namespace.

### 35. `kubectl apply -k kubernetes-manifests/`
* **Why:** To apply the new HPA manifest (`kubernetes-manifests/hpa.yaml`) and register it in `kustomization.yaml`.
* **Explanation:** We defined the autoscaler targeting the `frontend` deployment with a low CPU threshold (`10%`) to make it easy to trigger and observe scaling during load testing.

### 36. **Traffic Simulation & Monitoring Commands (The Loop)**
When testing autoscaling, we ran several commands repeatedly in order to monitor the behavior:

1. **`kubectl get hpa -w`**
   * **Why:** To watch the average CPU utilization of the pods and target replica counts.
   * **Reason for Repeated Use:** Running it with the `-w` (watch) flag streams changes in real-time. It allowed us to see exactly when CPU utilization crossed the 10% threshold and when the HPA requested a replica scale-up.
2. **`kubectl top pods`**
   * **Why:** To check the raw CPU and memory usage of each active pod.
   * **Reason for Repeated Use:** HPA averages CPU utilization over a period. Running `kubectl top pods` periodically gave us a raw, real-time snapshot of which individual frontend pods were taking the brunt of the traffic and how much CPU (in millicosres) they were drawing.
3. **`kubectl get pods -l app=frontend -w`**
   * **Why:** To observe the lifecycle of the frontend pods as they were created and destroyed.
   * **Reason for Repeated Use:** When HPA changes the replica counts, EKS schedules new pods. Using `-w` allowed us to watch new pods transition from `Pending` -> `ContainerCreating` -> `Running` in real-time, verifying that EKS had sufficient capacity to scale out.
4. **`kubectl logs -l app=loadgenerator --tail=50`**
   * **Why:** To monitor the request rate and check for errors from the load generators.
   * **Reason for Repeated Use:** This confirmed that the simulated users were actively hitting the web page without failing (e.g. returning 200 OKs) and showing the exact requests/second (rps) curve.

### 37. **Simulating Scale-Up**
* **Command:** `kubectl scale deployment/loadgenerator --replicas=3 && kubectl set env deployment/loadgenerator USERS=500`
* **Explanation:** This scaled the load testing pods to 3 replicas running 500 simulated users each (1,500 total). The wait time between requests was randomized, sending a massive stream of traffic (~80-100 requests per second) to the frontend.
* **Findings:** CPU surged to 17%, and the HPA successfully scaled the frontend pods from 1 to 5 replicas.

### 38. **Simulating Scale-Down**
* **Command:** `kubectl scale deployment/loadgenerator --replicas=1 && kubectl set env deployment/loadgenerator USERS=1`
* **Explanation:** This reduced traffic to 1 single simulated user to watch the system scale back down.
* **Findings:** Traffic ceased, and CPU usage dropped to near 0%. 
* *Note: The HPA waited for a default **5-minute cooldown period** before removing pods. This cooldown is a security feature built into Kubernetes to prevent pod thrashing (repeatedly scaling up and down due to temporary spikes).*

---

## Part 7: Client-side Access Issues (ELB vs HTTPS)

During testing, we verified the Load Balancer endpoint was public and healthy by running a `curl -I` request, which returned a successful `HTTP/1.1 200 OK`. However, accessing the link on other devices (like mobile phones) initially failed.

* **The Reason:** Modern browsers (Safari, Chrome on mobile) automatically upgrade unencrypted HTTP URLs (`http://`) to secure HTTPS URLs (`https://`). Since our AWS Load Balancer was configured to listen only on **HTTP (Port 80)** and had no SSL certificate set up for **HTTPS (Port 443)**, the mobile browser's connection request timed out.
* **The Solution:** Open the browser in **Incognito/Private mode** and explicitly type `http://` before the load balancer DNS hostname.

---

## Part 8: Setting up Jenkins (CI/CD) on EC2 & EKS Authentication Troubleshooting

### 39. `ssh -i "online-boutique-jenkins.pem" ubuntu@ec2-13-203-199-19.ap-south-1.compute.amazonaws.com`
* **Why:** To connect to the newly created Jenkins EC2 instance.
* **Findings:** Established SSH connection to the remote Ubuntu server.

### 40. `sudo apt update -y && sudo apt install -y openjdk-21-jdk`
* **Why:** Installed Java 21, as the latest Jenkins (2.555+) requires Java 21/25 and no longer supports Java 17.
* **Findings:** Successfully installed OpenJDK 21.

### 41. `curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null`
* **Why:** Downloaded the official 2026 repository GPG signing key to resolve the `NO_PUBKEY 7198F4B714ABFC68` signature verification error.
* **Findings:** Imported the valid signing key for package verification.

### 42. `echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list`
* **Why:** Registered the stable Jenkins debian repository source.
* **Findings:** Configured package source successfully.

### 43. `sudo apt update -y && sudo apt install -y jenkins`
* **Why:** Updated package lists and installed Jenkins.
* **Findings:** Installed and enabled the Jenkins system service.

### 44. `sudo systemctl status jenkins`
* **Why:** Checked if the Jenkins service was active and running.
* **Findings:** The service was successfully started (`active (running)`).

### 45. `sudo apt install -y docker.io && sudo systemctl enable --now docker`
* **Why:** Installed Docker daemon on the Jenkins server so Jenkins can build container images.
* **Findings:** Installed and launched the Docker daemon service.

### 46. `sudo usermod -aG docker jenkins && sudo usermod -aG docker ubuntu && sudo systemctl restart jenkins`
* **Why:** Added the `jenkins` system user to the `docker` security group, giving Jenkins permission to execute docker build/push commands without `sudo`.
* **Findings:** Successfully authorized Jenkins to run docker commands.

### 47. `sudo cat /var/lib/jenkins/secrets/initialAdminPassword`
* **Why:** Printed the initial admin setup password to register the admin account in the Jenkins Web UI.
* **Findings:** Retrived the admin security token.

### 48. `curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl`
* **Why:** Installed the `kubectl` CLI tool on the Jenkins server to allow Jenkins to deploy resources to EKS.
* **Findings:** Downloaded and installed `kubectl`.

### 49. `sudo apt install -y unzip && curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && unzip awscliv2.zip && sudo ./aws/install`
* **Why:** Installed the AWS CLI v2 on the Jenkins server to support AWS login and command executions in the pipeline.
* **Findings:** Installed `aws` CLI globally.

### 50. `aws sts get-caller-identity --profile user2` (Run locally)
* **Why:** Checked our exact IAM user name associated with `user2`.
* **Findings:** The IAM User ARN is `arn:aws:iam::553136990999:user/terraform-admin`.

### 51. `terraform workspace select dev && terraform apply -var="environment=dev" -var="cluster_name=online-boutique-eks-dev-dev" -auto-approve` (Run locally)
* **Why:** Applied the new `access_config` and `aws_eks_access_policy_association.default_user` changes locally using the correct workspace `dev`.
* **Findings:** Switched the EKS cluster to `API_AND_CONFIG_MAP` mode and granted cluster admin access to the default profile, resolving the EKS deploy authentication blockage.

### 52. `git pull origin main --rebase && git push origin main` (Run locally)
* **Why:** Pulled changes from GitHub, integrated our local fixes, and pushed the updated code to the remote repository.
* **Findings:** Synced local codebase with remote.

---

## Part 9: Directory Content Hashing & Local Cleanup

### 53. `docker image prune -a` (Run locally)
* **Why:** To clean up all local Docker images not currently associated with a running container to reclaim disk space after identifying that we had multiple tags and old builds cached locally.
* **Findings:** Reclaimed local disk space and pruned unused cached microservice image layers.

### 54. `git status` (Run locally)
* **Why:** To check the current state of modified files in the repository before finalizing the pipeline.
* **Findings:** Verified that the local workspace has the modified files for scripts, Jenkinsfile, docs, and Terraform configurations.

### 55. `git diff Jenkinsfile` (Run locally)
* **Why:** To review the changes applied to the Jenkins pipeline stages.
* **Findings:** Identified a naive `sed` command in Stage 4 of the Jenkinsfile that was failing to update manifests since it was matching `image: frontend` instead of the full ECR registry URL.

### 56. `bash -n scripts/build-push.sh && bash -n scripts/deploy.sh` (Run locally)
* **Why:** To check for syntax correctness in the updated shell scripts.
* **Findings:** The syntax was valid.

### 57. `aws ecr describe-images --repository-name online-boutique/frontend --image-ids imageTag=34e95c8` (Run locally)
* **Why:** To verify if a specific image tag exists in AWS ECR.
* **Findings:** Returned `ImageNotFoundException` because that specific hash-tag image had not been built or pushed yet, proving that the check works as a conditional check to skip builds.

### 58. `aws eks describe-nodegroup --cluster-name online-boutique-eks-dev --nodegroup-name online-boutique-eks-dev-app-nodes` (Run locally)
* **Why:** To inspect the EKS nodegroup status and identify the cause of the `CREATE_FAILED` status.
* **Findings:** Revealed `Unhealthy nodes in the kubernetes cluster`, which was caused by the nodes failing to join the cluster during creation when the subnet tags were mismatched.

### 59. `kubectl get nodes` (Run locally)
* **Why:** To check if worker nodes are connected to the cluster.
* **Findings:** Failed with a DNS lookup failure pointing to a stale cluster endpoint API domain hash (`F95D1...`).

### 60. `aws eks describe-cluster --name online-boutique-eks-dev` (Run locally)
* **Why:** To fetch the active EKS cluster configuration and endpoint from AWS.
* **Findings:** The active endpoint hash was `6EB7D...`, indicating that our local `kubeconfig` was out of date.

### 61. `aws eks update-kubeconfig --region ap-south-1 --name online-boutique-eks-dev` (Run locally)
* **Why:** To update the local `kubeconfig` to point to the active cluster endpoint.
* **Findings:** Successfully synchronized local kubectl config with the correct EKS API domain.

### 62. `kubectl get nodes` (Run locally - after update)
* **Why:** To list the cluster nodes after updating the endpoint.
* **Findings:** Failed with `the server has asked for the client to provide credentials` (Unauthorized) because the cluster creator was `terraform-admin` (profile `user2`), whereas normal laptop operations were run under `terra-user` (profile `default`), which has no EKS Access Entry.

### 63. `AWS_PROFILE=user2 terraform plan` (Run locally)
* **Why:** To dry-run Terraform using the authorized creator profile (`user2`) to verify the new access entry and node group recreation plan.
* **Findings:** Confirmed the plan will create access entries for `terra-user` and replace the tainted, failed node groups.

### 64. `git pull origin main` (Run locally)
* **Why:** To pull the latest changes from GitHub containing the account-agnostic manifests, S3 providers configuration, HPA adjustments, and optimized Jenkinsfile.
* **Findings:** Successfully updated 15 files and synchronized local codebase with remote.

### 65. `git add . && git commit -m "chore: dynamically inject S3 state bucket in deploy.sh and add local.tfvars to gitignore" && git push origin main` (Run locally)
* **Why:** To stage, commit, and push our final portability fixes (deploy.sh backend init script and gitignore overrides pattern) to the remote repository.
* **Findings:** Pushed successfully, updating origin/main from `8536a0d` to `62f86fd`.

---

## Part 10: EKS Access Recovery, Dynamic Kubeconfig & Jenkins Pipeline Resiliency

### 66. `aws sts get-caller-identity` (Run locally)
* **Why:** To identify which IAM principal is currently active in the local CLI session.
* **Findings:** Confirmed the active profile is `terra-user` (`arn:aws:iam::553136990999:user/terra-user`).

### 67. `cat ~/.kube/config` (Run locally)
* **Why:** To inspect the EKS cluster credentials configuration.
* **Findings:** Discovered that the EKS cluster user definition hardcoded `AWS_PROFILE = user2` (`terraform-admin`), forcing `kubectl` to use `terraform-admin` credentials instead of the active session's `terra-user` credentials.

### 68. `aws eks list-access-entries --cluster-name online-boutique-eks-dev` (Run locally)
* **Why:** To view the active EKS Access Entries and confirm which users have access.
* **Findings:** `terraform-admin` had an access entry, but `terra-user` did not.

### 69. `aws eks list-associated-access-policies --cluster-name online-boutique-eks-dev --principal-arn arn:aws:iam::553136990999:user/terraform-admin` (Run locally)
* **Why:** To check if `terraform-admin` has the admin access policy associated with its Access Entry.
* **Findings:** `associatedAccessPolicies` was empty. When `jenkins_iam_arn` was cleared in `terraform.tfvars`, Terraform destroyed the policy association resource, stripping `terraform-admin` of EKS permissions.

### 70. `aws eks associate-access-policy --cluster-name online-boutique-eks-dev --principal-arn arn:aws:iam::553136990999:user/terraform-admin --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy --access-scope type=cluster` (Run locally)
* **Why:** To manually associate the `AmazonEKSClusterAdminPolicy` back to `terraform-admin` on the `online-boutique-eks-dev` cluster to restore its permissions.
* **Findings:** Successfully associated.

### 71. `aws eks create-access-entry --cluster-name online-boutique-eks-dev --principal-arn arn:aws:iam::553136990999:user/terra-user --type STANDARD` (Run locally)
* **Why:** To register an EKS Access Entry for the active shell profile `terra-user` on the EKS cluster.
* **Findings:** Access Entry created.

### 72. `aws eks associate-access-policy --cluster-name online-boutique-eks-dev --principal-arn arn:aws:iam::553136990999:user/terra-user --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy --access-scope type=cluster` (Run locally)
* **Why:** To associate the cluster admin policy to the `terra-user` access entry.
* **Findings:** Successfully associated, giving `terra-user` EKS permissions.

### 73. `python3 fix_kubeconfig.py` (Run locally)
* **Why:** To run a script that edits `~/.kube/config` and removes the hardcoded `AWS_PROFILE=user2` env override block.
* **Findings:** Successfully modified the file, enabling `kubectl` to dynamically authenticate with the current shell's active profile (`terra-user`).

### 74. `kubectl get nodes` (Run locally - after fixes)
* **Why:** To test if EKS API access is restored for the active terminal user.
* **Findings:** Succeeded, listing the active nodes under `terra-user` directly.

### 75. `aws ec2 describe-instances --filters "Name=instance-state-name,Values=running"` (Run locally)
* **Why:** To check if there are running EC2 instances representing the Jenkins deployment.
* **Findings:** Identified a running instance named `jenkin-yuv` at `3.111.246.245`.

### 76. `aws eks list-access-entries --cluster-name online-boutique-eks-dev-dev` (Run locally)
* **Why:** The deployment script created a workspace-aware cluster `online-boutique-eks-dev-dev`. I ran this to check its access entries.
* **Findings:** `terra-user` (the creator) was present, but `terraform-admin` was missing.

### 77. `aws eks create-access-entry --cluster-name online-boutique-eks-dev-dev --principal-arn arn:aws:iam::553136990999:user/terraform-admin --type STANDARD` (Run locally)
* **Why:** To add `terraform-admin` as an access entry to the new `online-boutique-eks-dev-dev` cluster so the Jenkins server (which uses `terraform-admin` keys) can deploy to it.
* **Findings:** Entry created.

### 78. `aws eks associate-access-policy --cluster-name online-boutique-eks-dev-dev --principal-arn arn:aws:iam::553136990999:user/terraform-admin --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy --access-scope type=cluster` (Run locally)
* **Why:** To associate the admin access policy to `terraform-admin` on the new `online-boutique-eks-dev-dev` cluster.
* **Findings:** Successfully associated, authorizing the Jenkins CI/CD pipeline to deploy to the new cluster.

