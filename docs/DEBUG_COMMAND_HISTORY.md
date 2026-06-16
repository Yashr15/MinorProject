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
