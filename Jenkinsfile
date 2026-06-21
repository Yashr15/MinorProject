// ════════════════════════════════════════════════════════════════
// Jenkinsfile — CI/CD Pipeline for Online Boutique on AWS
// ════════════════════════════════════════════════════════════════
//
// This pipeline:
// 1. Checks out the source code
// 2. Logs into Amazon ECR
// 3. Builds Docker images for all 11 microservices
// 4. Pushes images to ECR
// 5. Deploys to EKS using kubectl
//
// PREREQUISITES:
// - Jenkins has AWS CLI + kubectl + Docker installed
// - Jenkins has AWS credentials configured (ID: 'aws-credentials')
// - EKS cluster is already running (created by Terraform)
// ════════════════════════════════════════════════════════════════

pipeline {
    agent any

    environment {
        AWS_REGION      = 'ap-south-1'
        AWS_ACCOUNT_ID  = credentials('aws-account-id')    // Store in Jenkins credentials
        ECR_REGISTRY    = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        PROJECT_NAME    = 'online-boutique'
        EKS_CLUSTER     = 'online-boutique-eks-dev'
        IMAGE_TAG       = "${BUILD_NUMBER}"
    }

    // List of all microservices to build
    // Each entry maps to: src/<service-name>/Dockerfile
    stages {

        // ─── Stage 1: Checkout ──────────────────────────
        stage('Checkout') {
            steps {
                checkout scm
                echo "✅ Source code checked out"
            }
        }

        // ─── Stage 2: ECR Login ─────────────────────────
        stage('ECR Login') {
            steps {
                withAWS(credentials: 'aws-credentials', region: "${AWS_REGION}") {
                    sh """
                        aws ecr get-login-password --region ${AWS_REGION} | \
                        docker login --username AWS --password-stdin ${ECR_REGISTRY}
                    """
                }
                echo "✅ Logged into ECR"
            }
        }

        // ─── Stage 3: Build & Push Images ───────────────
        stage('Build & Push Images') {
            steps {
                withAWS(credentials: 'aws-credentials', region: "${AWS_REGION}") {
                    script {
                        def services = [
                            'emailservice',
                            'productcatalogservice',
                            'recommendationservice',
                            'shippingservice',
                            'checkoutservice',
                            'paymentservice',
                            'currencyservice',
                            'cartservice',
                            'frontend',
                            'adservice',
                            'loadgenerator'
                        ]

                        // Special cases: some services have Dockerfiles in subdirectories
                        def dockerContextMap = [
                            'cartservice': 'src/cartservice/src'
                        ]

                        for (svc in services) {
                            def context = dockerContextMap.get(svc, "src/${svc}")
                            def ecrRepo = "${ECR_REGISTRY}/${PROJECT_NAME}/${svc}"

                            // Calculate directory-specific git commit hash
                            def svcTag = sh(script: "git log -1 --format='%h' -- ${context} 2>/dev/null || echo 'latest'", returnStdout: true).trim()

                            // Check if image with this hash already exists in ECR
                            def imageExists = sh(
                                script: "aws ecr describe-images --repository-name ${PROJECT_NAME}/${svc} --image-ids imageTag=${svcTag} >/dev/null 2>&1 && echo 'true' || echo 'false'",
                                returnStdout: true
                            ).trim()

                            if (imageExists == 'true') {
                                echo "⏭️ Image ${ecrRepo}:${svcTag} already exists in ECR. Skipping build and push."
                            } else {
                                echo "🔨 Building ${svc} (tag: ${svcTag})..."
                                sh """
                                    docker build -t ${ecrRepo}:${svcTag} \
                                                 -t ${ecrRepo}:latest \
                                                 ${context}
                                """

                                echo "📤 Pushing ${svc}..."
                                sh """
                                    docker push ${ecrRepo}:${svcTag}
                                    docker push ${ecrRepo}:latest
                                """
                            }
                        }
                    }
                }
                echo "✅ Necessary images built and pushed"
            }
        }

        // ─── Stage 4: Update K8s Manifests ──────────────
        stage('Update Manifests') {
            steps {
                script {
                    def services = [
                        'emailservice',
                        'productcatalogservice',
                        'recommendationservice',
                        'shippingservice',
                        'checkoutservice',
                        'paymentservice',
                        'currencyservice',
                        'cartservice',
                        'frontend',
                        'adservice',
                        'loadgenerator'
                    ]

                    def dockerContextMap = [
                        'cartservice': 'src/cartservice/src'
                    ]

                    for (svc in services) {
                        def context = dockerContextMap.get(svc, "src/${svc}")
                        def svcTag = sh(script: "git log -1 --format='%h' -- ${context} 2>/dev/null || echo 'latest'", returnStdout: true).trim()
                        def ecrImage = "${ECR_REGISTRY}/${PROJECT_NAME}/${svc}:${svcTag}"

                        // Replace image name in K8s manifest with full ECR URL
                        sh """
                            sed -E -i 's|image:[[:space:]]*([^[:space:]]+/)?${svc}(:[^[:space:]]+)?([[:space:]]+.*)?\$|image: ${ecrImage}|g' \
                                kubernetes-manifests/${svc}.yaml || true
                        """
                    }
                }
                echo "✅ Manifests updated with ECR image URLs"
            }
        }

        // ─── Stage 5: Deploy to EKS ────────────────────
        stage('Deploy to EKS') {
            steps {
                withAWS(credentials: 'aws-credentials', region: "${AWS_REGION}") {
                    sh """
                        # Configure kubectl to talk to EKS
                        aws eks update-kubeconfig \
                            --region ${AWS_REGION} \
                            --name ${EKS_CLUSTER}

                        # Deploy all manifests
                        kubectl apply -k kubernetes-manifests/

                        # Wait for rollout
                        echo "⏳ Waiting for deployments to be ready..."
                        kubectl rollout status deployment/frontend --timeout=120s
                        kubectl rollout status deployment/cartservice --timeout=120s

                        # Show the external URL
                        echo "🌐 Frontend URL:"
                        kubectl get svc frontend-external -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
                        echo ""
                    """
                }
                echo "✅ Deployed to EKS!"
            }
        }
    }

    post {
        success {
            echo """
            ╔══════════════════════════════════════╗
            ║   ✅ DEPLOYMENT SUCCESSFUL!          ║
            ║   Build: #${BUILD_NUMBER}            ║
            ╚══════════════════════════════════════╝
            """
        }
        failure {
            echo """
            ╔══════════════════════════════════════╗
            ║   ❌ DEPLOYMENT FAILED!              ║
            ║   Check logs for details.            ║
            ╚══════════════════════════════════════╝
            """
        }
        always {
            // Clean up Docker images to save disk space
            sh 'docker system prune -f || true'
        }
    }
}
