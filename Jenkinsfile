pipeline {
    agent any

    environment {
        AWS_REGION = 'ap-south-1'
        AWS_ACCOUNT_ID = '892334471137'
        ECR_REPOSITORY = 'hotstar-clone'
        ECR_REGISTRY = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    }

    stages {

        stage('Checkout') {
            steps {
                git branch: 'main',
                    url: 'https://github.com/aakashrsethi39/hotstar-devsecops.git'

                script {
                    env.IMAGE_TAG = sh(
                        script: 'git rev-parse --short HEAD',
                        returnStdout: true
                    ).trim()

                    if (!env.IMAGE_TAG) {
                        error('IMAGE_TAG could not be determined from Git')
                    }

                    echo "Git commit SHA: ${env.IMAGE_TAG}"
                } 
            }
        }

        stage('SonarQube Scan') {
            steps {
                script {
                    def scannerHome = tool 'SonarScanner'

                    withSonarQubeEnv('SonarQube') {
                        sh """
                            ${scannerHome}/bin/sonar-scanner \
                              -Dsonar.projectKey=hotstar-clone \
                              -Dsonar.sources=app \
                              -Dsonar.exclusions=app/node_modules/**,app/build/**,**/zap-report.*,**/*-report.*
                        """
                    }
                }
            }
        }

        stage('SonarQube Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Trivy Filesystem Scan') {
            steps {
                sh '''
                    trivy fs \
                      --severity HIGH,CRITICAL \
                      --exit-code 1 \
                      .
                '''
            }
        }

        stage('Docker Build') {
            steps {
                withCredentials([
                    string(
                        credentialsId: 'tmdb-api-key',
                        variable: 'TMDB_API_KEY'
                    )
                ]) {
                    sh '''
                        docker build \
                          --build-arg REACT_APP_TMDB_API_KEY="$TMDB_API_KEY" \
                          -t ${ECR_REPOSITORY}:${IMAGE_TAG} \
                          .
                    '''
                }
            }
        }

        stage('Trivy Image Scan') {
            steps {
                sh '''
                    trivy image \
                      --severity HIGH,CRITICAL \
                      --exit-code 1 \
                      ${ECR_REPOSITORY}:${IMAGE_TAG}
                '''
            }
        }

        stage('Docker Scout Scan') {
            steps {
                sh '''
                    echo "Running Docker Scout vulnerability scan..."

                    docker scout cves \
                        --only-severity high,critical \
                        --exit-code \
                        --format sarif \
                        --output "$WORKSPACE/scout-report.sarif.json" \
                        ${ECR_REPOSITORY}:${IMAGE_TAG}

                    echo "Docker Scout security gate passed."
                '''
            }
        }

        stage('ECR Login') {
            steps {
                sh '''
                    aws ecr get-login-password \
                      --region ${AWS_REGION} | \
                    docker login \
                      --username AWS \
                      --password-stdin \
                      ${ECR_REGISTRY}
                '''
            }
        }

        stage('Tag Image') {
            steps {
                sh '''
                    docker tag \
                      ${ECR_REPOSITORY}:${IMAGE_TAG} \
                      ${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}
                '''
            }
        }

        stage('Push to ECR') {
            steps {
                sh '''
                    docker push \
                      ${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}
                '''
            }
        }

        stage('Update GitOps Manifest') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'github-infra-write',
                        usernameVariable: 'GIT_USERNAME',
                        passwordVariable: 'GIT_TOKEN'
                    )
                ]) {
                    sh '''
                        set -e

                        echo "Cloning GitOps repository..."

                        rm -rf infra-repo

                        git clone \
                            https://${GIT_USERNAME}:${GIT_TOKEN}@github.com/aakashrsethi39/hotstar-dev-secops.git \
                            infra-repo

                        cd infra-repo

                        echo "Updating Kubernetes image to ${IMAGE_TAG}..."

                        sed -i "s|image: .*hotstar-clone.*|image: 892334471137.dkr.ecr.ap-south-1.amazonaws.com/hotstar-clone:${IMAGE_TAG}|" k8s/deployment.yaml

                        echo "Updated image:"
                        grep "image:" k8s/deployment.yaml

                        git config user.name "Jenkins"
                        git config user.email "jenkins@localhost"

                        git add k8s/deployment.yaml

                        if git diff --cached --quiet; then
                            echo "No image change detected."
                            exit 0
                        fi

                        git commit -m "Update Hotstar image to ${IMAGE_TAG}"

                        echo "Pushing GitOps change..."

                        git push origin main

                        echo "GitOps repository updated successfully."
                    '''
                }
            }
        }
        stage('Post-Deployment Verification') {
            steps {
                sh '''
                    set -e

                    echo "Waiting for Argo CD to deploy image ${IMAGE_TAG}..."

                    EXPECTED_IMAGE="892334471137.dkr.ecr.ap-south-1.amazonaws.com/hotstar-clone:${IMAGE_TAG}"

                    for i in $(seq 1 60); do

                        CURRENT_IMAGE=$(kubectl get deployment hotstar-clone \
                            -o jsonpath='{.spec.template.spec.containers[0].image}' \
                            2>/dev/null || true)

                        echo "Current image: ${CURRENT_IMAGE}"

                        if [ "$CURRENT_IMAGE" = "$EXPECTED_IMAGE" ]; then
                            echo "Argo CD has deployed the expected image."
                            break
                        fi

                        if [ "$i" -eq 60 ]; then
                            echo "ERROR: Argo CD did not deploy ${EXPECTED_IMAGE}"
                            exit 1
                        fi

                        echo "Waiting for Argo CD reconciliation..."
                        sleep 5
                    done

                    echo "Waiting for Kubernetes rollout..."

                    kubectl rollout status deployment/hotstar-clone --timeout=180s

                    echo "Checking deployment..."
                    kubectl get deployment hotstar-clone

                    echo "Checking pods..."
                    kubectl get pods -l app=hotstar-clone -o wide

                    echo "Checking service..."
                    kubectl get svc hotstar-clone

                    echo "Waiting for LoadBalancer hostname..."

                    ALB_URL=""

                    for i in $(seq 1 30); do
                        ALB_URL=$(kubectl get svc hotstar-clone \
                            -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' \
                            2>/dev/null || true)

                        if [ -n "$ALB_URL" ]; then
                            break
                        fi

                        echo "LoadBalancer hostname not available yet..."
                        sleep 10
                    done

                    if [ -z "$ALB_URL" ]; then
                        echo "ERROR: LoadBalancer hostname was not assigned."
                        exit 1
                    fi

                    echo "Application URL: http://${ALB_URL}"

                    echo "Checking HTTP response..."

                    HTTP_STATUS=$(curl -L -s -o /dev/null \
                        -w "%{http_code}" \
                        --max-time 15 \
                        "http://${ALB_URL}/")

                    echo "HTTP status: ${HTTP_STATUS}"

                    if [ "$HTTP_STATUS" -lt 200 ] || [ "$HTTP_STATUS" -ge 400 ]; then
                        echo "ERROR: Application health check failed."
                        exit 1
                    fi

                    echo "Application verification successful."
                '''
            }
        }

        stage('OWASP ZAP DAST') {
            steps {
                sh '''
                    ALB_URL=$(kubectl get svc hotstar-clone \
                        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

                    echo "Scanning: http://${ALB_URL}"

                    /opt/zap/zap.sh \
                        -cmd \
                        -port 8090 \
                        -quickurl "http://${ALB_URL}" \
                        -quickout "$WORKSPACE/zap-report.json" \
                        -quickprogress

                    echo "ZAP scan completed."

                    echo "ZAP findings:"
                    jq '
                        [.site[]?.alerts[]? | .riskcode]
                        | group_by(.)
                        | map({
                            riskcode: .[0],
                            count: length
                        })
                    ' "$WORKSPACE/zap-report.json"

                    HIGH_COUNT=$(jq '
                        [.site[]?.alerts[]? | select(.riskcode == "3")]
                        | length
                    ' "$WORKSPACE/zap-report.json")

                    echo "High-risk findings: ${HIGH_COUNT}"

                    if [ "$HIGH_COUNT" -gt 0 ]; then
                        echo "ERROR: ZAP found HIGH-risk vulnerabilities."
                        exit 1
                    fi

                    echo "ZAP security gate passed."
                '''
            }
        }
    }

    post {
        always {
            archiveArtifacts \
                artifacts: 'zap-report.json, scout-report.sarif.json',
                allowEmptyArchive: true
        }
    }
}