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
                              -Dsonar.sources=.
                        """
                    }
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
                          -t ${ECR_REPOSITORY}:${BUILD_NUMBER} \
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
                      ${ECR_REPOSITORY}:${BUILD_NUMBER}
                '''
            }
        }

        stage('Docker Scout Scan') {
            steps {
                sh '''
                    docker scout quickview \
                      ${ECR_REPOSITORY}:${BUILD_NUMBER}
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
                      ${ECR_REPOSITORY}:${BUILD_NUMBER} \
                      ${ECR_REGISTRY}/${ECR_REPOSITORY}:${BUILD_NUMBER}
                '''
            }
        }

        stage('Push to ECR') {
            steps {
                sh '''
                    docker push \
                      ${ECR_REGISTRY}/${ECR_REPOSITORY}:${BUILD_NUMBER}
                '''
            }
        }

        stage('Deploy to EKS') {
            steps {
                sh '''
                    rm -rf infra-repo

                    git clone \
                        https://github.com/aakashrsethi39/hotstar-dev-secops.git \
                        infra-repo

                    cd infra-repo

                    sed -i "s/IMAGE_TAG/${BUILD_NUMBER}/g" k8s/deployment.yaml

                    kubectl apply -f k8s/

                    if ! kubectl rollout status \
                        deployment/hotstar-clone \
                        --timeout=120s; then

                        echo "Deployment failed!"
                        echo "Rolling back to previous version..."

                        kubectl rollout undo deployment/hotstar-clone

                        kubectl rollout status \
                            deployment/hotstar-clone \
                            --timeout=120s

                        echo "Rollback completed."

                        exit 1
                    fi

                    echo "Deployment successful."
                '''
            }
        }

        stage('Post-Deployment Verification') {
            steps {
                sh '''
                    echo "Checking deployment..."

                    kubectl get deployment hotstar-clone

                    echo "Checking pods..."

                    kubectl get pods \
                        -l app=hotstar-clone \
                        -o wide

                    echo "Checking service..."

                    kubectl get svc hotstar-clone

                    echo "Waiting for LoadBalancer hostname..."

                    for i in $(seq 1 30); do
                        ALB_URL=$(kubectl get svc hotstar-clone \
                            -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)

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

                    HTTP_STATUS=$(curl -L \
                        -s \
                        -o /dev/null \
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
                        -quickout "$WORKSPACE/zap-report.html" \
                        -quickprogress
                '''
            }
        }
    }

    post {
        always {
            archiveArtifacts \
                artifacts: 'zap-report.html',
                allowEmptyArchive: true
        }
    }
}