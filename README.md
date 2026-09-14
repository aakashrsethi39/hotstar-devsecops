# Hotstar DevSecOps CI/CD on AWS EKS

A complete DevSecOps CI/CD implementation for a React-based Hotstar clone running on Amazon EKS.

The project integrates Infrastructure as Code, CI/CD, container security, static and dynamic security testing, GitOps, Kubernetes autoscaling, monitoring, alerting, and automated deployment verification.

---

# Part 1 — Project Objective

The objective of this project is to build an end-to-end secure CI/CD pipeline for a Hotstar clone application.

The final workflow is:

Developer
   ↓
GitHub
   ↓
Jenkins
   ↓
SonarQube
   ↓
Trivy
   ↓
Docker
   ↓
Docker Scout
   ↓
Amazon ECR
   ↓
GitOps Repository
   ↓
Argo CD
   ↓
Amazon EKS
   ↓
Kubernetes
   ↓
HPA
   ↓
Prometheus
   ↓
Grafana
   ↓
Alerting
   ↓
OWASP ZAP

The project was implemented using two separate GitHub repositories:

1. Application repository
2. Infrastructure/GitOps repository

This separation allows application development and Kubernetes deployment configuration to follow a GitOps architecture.

---

# Part 2 — Application Repository

The application repository contains the Hotstar clone source code and CI/CD configuration.

Repository:

https://github.com/aakashrsethi39/hotstar-devsecops

Main structure:

    hotstar-devsecops/
    ├── app/
    ├── Dockerfile
    ├── Jenkinsfile
    └── README.md

The React application is located inside the `app` directory.

The project uses:

- React
- TypeScript
- npm
- react-scripts
- Nginx for production serving

The application repository is the source repository monitored by Jenkins.

---

# Part 3 — Infrastructure / GitOps Repository

A separate repository was created for AWS infrastructure, Jenkins configuration, Kubernetes manifests, and GitOps configuration.

Repository:

https://github.com/aakashrsethi39/hotstar-dev-secops

Structure:

    hotstar-dev-secops/
    ├── application/
    ├── jenkins/
    ├── k8s/
    └── terraform/

The separation provides:

    Application Repository
            ↓
        Jenkins CI
            ↓
    Infrastructure/GitOps Repository
            ↓
         Argo CD
            ↓
          EKS

Jenkins does not directly modify Kubernetes resources as the final deployment mechanism.

Instead, Jenkins updates the desired image in Git, and Argo CD synchronizes the Kubernetes cluster.

---

# Part 4 — AWS Region and Project Networking

The project was implemented in:

    ap-south-1

The main VPC uses:

    10.0.0.0/16

Two Availability Zones were used.

Public subnets:

    10.0.1.0/24
    10.0.2.0/24

Private subnets:

    10.0.11.0/24
    10.0.12.0/24

The architecture is:

    Internet
       |
       v
    Internet Gateway
       |
       v
    Public Subnets
       |
       +---- Jenkins / ALB
       |
       +---- NAT Gateway
                 |
                 v
            Private Subnets
                 |
                 v
                EKS

EKS worker nodes run inside the private subnets.

The VPC was created as a reusable Terraform module.

---

# Part 5 — Terraform Infrastructure as Code

Terraform was used to provision the AWS infrastructure instead of creating resources manually.

Terraform root directory:

    ~/hotstar-dev-secops/terraform

Structure:

    terraform/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── providers.tf
    ├── terraform.tfvars
    └── modules/
        ├── vpc/
        ├── iam/
        ├── ecr/
        ├── eks/
        ├── jenkins/
        └── sonarqube/

The VPC module provides:

- VPC
- Public subnets
- Private subnets
- Internet Gateway
- NAT Gateways
- Route tables
- Route associations
- Subnet tagging

The EKS module provisions:

- EKS cluster
- Managed node group
- Cluster IAM role
- Node IAM role
- Security configuration

Additional Terraform modules were created for:

- IAM
- ECR
- Jenkins
- SonarQube

The infrastructure therefore becomes reproducible through:

    terraform init
    terraform plan
    terraform apply

---

# Part 6 — Terraform Backend / Bootstrap

Terraform state management was separated from the main infrastructure deployment.

The bootstrap process was used to create the resources required for Terraform state management.

The backend uses AWS services so Terraform state does not remain only on the local machine.

The overall workflow is:

    Bootstrap
       |
       +---- S3
       |
       +---- State locking
       |
       v
    Terraform Infrastructure
       |
       +---- VPC
       +---- IAM
       +---- ECR
       +---- EKS
       +---- Jenkins
       +---- SonarQube

The Terraform backend protects the shared infrastructure state and allows Terraform to consistently track resources.

The project also encountered and resolved Terraform state-locking issues during implementation.

A stale lock was force-unlocked when required using:

    terraform force-unlock <LOCK_ID>

The important lesson from the implementation was to verify the Terraform state and lock before running another apply.

---

# Part 7 — IAM Roles and Policies

IAM roles were created for the AWS components used by the project.

The main roles were:

    hotstar-eks-cluster-role
    hotstar-eks-node-role
    hotstar-jenkins-role

## EKS Cluster Role

The EKS cluster role was configured with:

    AmazonEKSClusterPolicy

This allows Amazon EKS to manage the required AWS resources for the Kubernetes control plane.

## EKS Node Role

The worker-node role was configured with:

    AmazonEKSWorkerNodePolicy
    AmazonEC2ContainerRegistryPullOnly
    AmazonEKS_CNI_Policy

These permissions allow worker nodes to:

- Join the EKS cluster
- Pull images from ECR
- Use the AWS VPC CNI
- Communicate with required AWS services

## Jenkins Role

Jenkins runs on an EC2 instance and uses an IAM instance profile.

The instance profile:

    hotstar-jenkins-instance-profile

is attached to the Jenkins EC2 instance.

For this learning project, the Jenkins role was given administrative permissions to simplify AWS integration.

In a production environment, this should be replaced with least-privilege permissions.

The important design principle is:

    Jenkins EC2
        |
        v
    IAM Instance Profile
        |
        v
    AWS APIs

No long-lived AWS access keys were required on the Jenkins server.

---

# Part 8 — Amazon ECR Repository

Amazon Elastic Container Registry was created to store the application Docker images.

Repository:

    hotstar-clone

Region:

    ap-south-1

AWS account:

    892334471137

The ECR image path is:

    892334471137.dkr.ecr.ap-south-1.amazonaws.com/hotstar-clone

The repository was configured for image scanning.

The pipeline generates an image tag from the Git commit:

    IMAGE_TAG=$(git rev-parse --short HEAD)

For example:

    f28c9cf

The resulting image becomes:

    hotstar-clone:f28c9cf

and is pushed to:

    892334471137.dkr.ecr.ap-south-1.amazonaws.com/hotstar-clone:f28c9cf

This gives every application image a direct relationship with a Git commit.

The flow is:

    Git Commit
        |
        v
    Git SHA
        |
        v
    Docker Image Tag
        |
        v
    ECR
        |
        v
    Kubernetes

Useful command:

    aws ecr describe-images \
      --repository-name hotstar-clone \
      --region ap-south-1

---

# Part 9 — Amazon EKS Cluster

The Kubernetes platform was created using Amazon EKS.

Cluster name:

    hotstar-eks

Region:

    ap-south-1

The EKS cluster was provisioned through Terraform.

The cluster uses the VPC created in the earlier Terraform stages.

The EKS control plane manages:

- Kubernetes API server
- Scheduler
- Controller manager
- Cluster state

Worker nodes run separately in the configured private subnets.

The final architecture is:

    Terraform
       |
       v
    Amazon EKS
       |
       +------------------+
       |                  |
       v                  v
    Control Plane     Worker Nodes
                           |
                           v
                    Kubernetes Pods

The EKS cluster was eventually upgraded to Kubernetes 1.35 during the implementation.

The active EKS version was verified using:

    aws eks describe-cluster \
      --name hotstar-eks \
      --region ap-south-1

---

# Part 10 — EKS Managed Node Group

A managed node group was created for the EKS cluster.

Node group:

    hotstar-eks-nodes

The worker nodes use:

    t3.small

The node group was configured with autoscaling boundaries.

Final operational scaling configuration:

    Minimum: 2
    Desired: 4
    Maximum: 4

The node count was increased during the monitoring phase because the Kubernetes monitoring stack caused memory pressure on the smaller nodes.

The scaling operation was performed using:

    aws eks update-nodegroup-config \
      --cluster-name hotstar-eks \
      --nodegroup-name hotstar-eks-nodes \
      --scaling-config minSize=2,maxSize=4,desiredSize=4

The final cluster contained four Ready worker nodes.

The nodes were verified using:

    kubectl get nodes

Example:

    NAME                                           STATUS
    ip-10-0-11-202.ap-south-1.compute.internal     Ready
    ip-10-0-11-9.ap-south-1.compute.internal       Ready
    ip-10-0-12-16.ap-south-1.compute.internal      Ready
    ip-10-0-12-82.ap-south-1.compute.internal      Ready

The project deliberately used small instances to control AWS learning costs.

---

# Part 11 — Jenkins EC2 Server

Jenkins was deployed on a dedicated EC2 instance instead of inside the EKS cluster.

This provides a clear separation between:

    CI Server
        |
        v
    Kubernetes Platform

The Jenkins server performs:

- Git checkout
- SonarQube scanning
- Trivy scanning
- Docker builds
- Docker Scout scanning
- ECR authentication
- ECR image push
- GitOps repository modification
- Kubernetes verification
- OWASP ZAP scanning

The Jenkins workspace is:

    /var/lib/jenkins/workspace/hotstar-devsecops

The Jenkins server also contains the tools required by the pipeline, including:

    Docker
    AWS CLI
    kubectl
    Trivy
    Docker Scout
    OWASP ZAP
    jq

Jenkins receives AWS permissions through its EC2 IAM role.

Therefore the pipeline can execute AWS operations without storing static AWS credentials on the machine.

---

# Part 12 — Jenkins Application Load Balancer and GitHub Webhook

An Application Load Balancer was created for Jenkins so GitHub can communicate with Jenkins through a stable endpoint.

The Jenkins ALB hostname was:

    hotstar-jenkins-alb-1743321616.ap-south-1.elb.amazonaws.com

The traffic flow is:

    GitHub
       |
       | HTTP Webhook
       v
    Jenkins ALB
       |
       v
    Jenkins EC2
       |
       v
    Jenkins Pipeline

The Jenkins ALB uses a security group allowing HTTP traffic on port 80.

The Jenkins instance is behind the ALB rather than being directly exposed as the GitHub webhook target.

The GitHub webhook points to:

    http://hotstar-jenkins-alb-1743321616.ap-south-1.elb.amazonaws.com/github-webhook/

The purpose of the webhook is to automatically trigger Jenkins when changes are pushed to the application repository.

The complete trigger flow is:

    Developer
        |
        | git push
        v
    GitHub
        |
        | webhook
        v
    Jenkins ALB
        |
        v
    Jenkins
        |
        v
    Pipeline starts

This removes the need to manually click "Build Now" for normal development changes.

---

# Part 13 — SonarQube EC2 Server

SonarQube was deployed on a separate EC2 instance to perform static code analysis.

The SonarQube server was kept separate from Jenkins.

Architecture:

    Jenkins EC2
         |
         | Private Network
         v
    SonarQube EC2
         |
         v
    SonarQube :9000

SonarQube private IP:

    10.0.2.109

SonarQube version used:

    9.9.8.100196

The Jenkins security group was allowed to access SonarQube on:

    TCP 9000

Connectivity was verified from Jenkins:

    curl http://10.0.2.109:9000

The SonarQube health API returned:

    UP

This confirmed that Jenkins could communicate with SonarQube through the private VPC network.

---

# Part 14 — SonarQube Project and Jenkins Integration

A SonarQube project was created for the Hotstar application.

Project:

    hotstar-clone

Jenkins was configured with the SonarQube server.

The Jenkins pipeline performs the SonarQube analysis against:

    app/

The pipeline also excludes generated files and security reports from the analysis.

Important exclusions include:

    app/node_modules/**
    app/build/**
    **/zap-report.*
    **/*-report.*

The pipeline waits for the SonarQube Quality Gate after the scan.

The workflow is:

    Jenkins
       |
       v
    SonarQube Scan
       |
       v
    Quality Gate
       |
       +------ PASS ------> Continue Pipeline
       |
       +------ FAIL ------> Stop Pipeline

This makes SonarQube the first major security/quality gate in the CI pipeline.

---

# Part 15 — SonarQube Webhook

A SonarQube webhook was configured so SonarQube can notify Jenkins when analysis is complete.

Webhook:

    http://hotstar-jenkins-alb-1743321616.ap-south-1.elb.amazonaws.com/sonarqube-webhook/

The Jenkins ALB receives the request and forwards it to Jenkins.

Connectivity was tested successfully.

A request to the endpoint returned:

    HTTP 405

The 405 response confirmed that the endpoint was reachable but that the test HTTP method was not the expected webhook method.

The resulting flow is:

    Jenkins
       |
       | Start SonarQube analysis
       v
    SonarQube
       |
       | Analysis completed
       v
    SonarQube Webhook
       |
       v
    Jenkins
       |
       v
    Quality Gate Result

---

# Part 16 — Application Dockerfile

The React application was containerized using Docker.

The Docker image uses a build stage to create the production React application and Nginx to serve the generated static files.

The resulting container exposes:

    8080

The container was also hardened to avoid running the application as root.

The final flow is:

    React Source
        |
        v
    npm build
        |
        v
    Production Build
        |
        v
    Nginx Container
        |
        v
    Port 8080

The container was tested locally before being integrated into Jenkins.

Example validation:

    curl -I http://localhost:8081

Expected response:

    HTTP/1.1 200 OK

This confirmed that the container was serving the React application successfully.

---

# Part 17 — Fixing Application Dependencies

During implementation, dependency and package-version problems were identified.

The React application originally contained an invalid TypeScript version.

The dependency was corrected to a compatible version:

    TypeScript 4.9.5

The application dependencies were also reviewed using npm audit.

The pipeline was subsequently integrated with Trivy to detect dependency vulnerabilities.

The purpose of this stage was to ensure that dependency problems are identified before the Docker image reaches ECR.

The dependency security flow became:

    package.json
         |
         v
    package-lock.json
         |
         v
    Trivy Filesystem Scan
         |
         v
    Docker Build
         |
         v
    Trivy Image Scan

---

# Part 18 — TMDB API Configuration

The Hotstar clone uses TMDB API data to retrieve movie information.

The API configuration was moved into an environment file:

    app/.env

The `.env` file was added to `.gitignore` so the API key is not committed to GitHub.

The application therefore uses:

    REACT_APP_*

environment variables during the React build.

Important security consideration:

React environment variables are embedded into the generated frontend bundle.

Therefore a frontend API key must not be treated as a true secret.

Any exposed API key should be rotated and restricted appropriately.

No API keys, passwords, tokens, or other secrets should be committed to this repository or included in this README.

---

# Part 19 — Jenkins Credentials

Jenkins credentials were configured for services that require authentication.

One important credential is:

    github-infra-write

This credential allows Jenkins to update the GitOps repository.

The GitHub credential is restricted to the infrastructure/GitOps repository:

    aakashrsethi39/hotstar-dev-secops

Required repository permissions include:

    Contents: Read and Write
    Metadata: Read-only

Jenkins uses the credential when it clones and pushes the GitOps repository.

The credential itself is never written directly into the Jenkinsfile.

The pipeline references the Jenkins credential ID instead.

Example concept:

    credentialsId: 'github-infra-write'

This prevents sensitive credentials from being hard-coded into the pipeline.

---

# Part 20 — Jenkins Pipeline Structure

The Jenkins pipeline was implemented using a Jenkinsfile stored in the application repository.

The pipeline contains the following major stages:

    1. Checkout
    2. SonarQube Scan
    3. SonarQube Quality Gate
    4. Trivy Filesystem Scan
    5. Docker Build
    6. Trivy Image Scan
    7. Docker Scout Scan
    8. ECR Login
    9. Tag Image
    10. Push to ECR
    11. Update GitOps Manifest
    12. Post-Deployment Verification
    13. OWASP ZAP DAST

The pipeline therefore follows:

    Source
      ↓
    Analyze
      ↓
    Scan
      ↓
    Build
      ↓
    Scan Image
      ↓
    Push
      ↓
    GitOps
      ↓
    Deploy
      ↓
    Verify
      ↓
    DAST

The pipeline is triggered by GitHub changes rather than requiring a manual Jenkins build.

---

# Part 21 — Git Commit SHA Image Tagging

The pipeline does not use a generic image tag such as:

    latest

Instead, the Git commit SHA is used as the image tag.

The pipeline obtains the SHA using:

    git rev-parse --short HEAD

Example:

    f28c9cf

The Docker image becomes:

    hotstar-clone:f28c9cf

The ECR image becomes:

    892334471137.dkr.ecr.ap-south-1.amazonaws.com/hotstar-clone:f28c9cf

This provides traceability.

For example:

    Git Commit f28c9cf
          |
          v
    Docker Image f28c9cf
          |
          v
    ECR Image f28c9cf
          |
          v
    Kubernetes Deployment f28c9cf

This makes it possible to identify exactly which source revision is deployed.

---

# Part 22 — Trivy Filesystem Security Scan

Trivy was installed on the Jenkins server to scan the application before Docker image creation.

The filesystem scan checks the application dependencies and files for known vulnerabilities.

The pipeline performs:

    Source Checkout
          |
          v
    Trivy Filesystem Scan
          |
          +------ Vulnerability ------> Pipeline Stops
          |
          v
        Docker Build

The application dependency issues discovered during development were addressed before the final successful pipeline.

This provides an early security gate before the application is packaged into a container.

---

# Part 23 — Docker Build and Container Security

After the filesystem security scan passes, Jenkins builds the Docker image.

Example:

    docker build \
      -t hotstar-clone:${IMAGE_TAG} .

The resulting image is then scanned before being pushed.

The container image was hardened by:

- Using a production Nginx image
- Serving only the generated React build
- Avoiding unnecessary packages
- Running the Nginx process without root privileges
- Keeping the container focused on serving the application

The image was locally tested before ECR deployment.

---

# Part 24 — Trivy Container Image Scan

Trivy was also used to scan the completed Docker image.

Example:

    trivy image hotstar-clone:${IMAGE_TAG}

This scan is important because the final Docker image can contain vulnerabilities that are not obvious from the source code.

The scan evaluates:

    Application Dependencies
    +
    OS Packages
    +
    Container Base Image
    +
    Installed Libraries

The successful final image scan produced:

    Vulnerabilities: 0

This allowed the pipeline to proceed to Docker Scout and ECR.

---

# Part 25 — Docker Scout Security Scan

Docker Scout was added as an additional container security layer.

Docker Scout was initially not available on the Jenkins server.

It was installed and verified.

Docker version used during implementation:

    Docker 29.1.3

The image was scanned using:

    docker scout cves \
      --only-severity high,critical \
      --exit-code \
      --format sarif \
      --output scout-report.sarif.json \
      hotstar-clone:${IMAGE_TAG}

The successful scan produced:

    High: 0
    Critical: 0

The SARIF report was archived by Jenkins for evidence.

This provides another independent security check before the image is pushed to ECR.

---

# Part 26 — Push Secure Image to ECR

Once all security stages pass, Jenkins authenticates with Amazon ECR.

Authentication:

    aws ecr get-login-password \
      --region ap-south-1 |
    docker login \
      --username AWS \
      --password-stdin \
      892334471137.dkr.ecr.ap-south-1.amazonaws.com

The image is tagged:

    docker tag \
      hotstar-clone:${IMAGE_TAG} \
      892334471137.dkr.ecr.ap-south-1.amazonaws.com/hotstar-clone:${IMAGE_TAG}

Then pushed:

    docker push \
      892334471137.dkr.ecr.ap-south-1.amazonaws.com/hotstar-clone:${IMAGE_TAG}

At this point the secure image is available to the EKS worker nodes through ECR.

The deployment flow becomes:

    Jenkins
       |
       v
    Secure Docker Image
       |
       v
    Amazon ECR
       |
       v
    Kubernetes

    ---

    # Part 27 — Kubernetes Manifests

After the container image was pushed to Amazon ECR, Kubernetes manifests were created in the GitOps repository.

The Kubernetes configuration is stored under:

    k8s/

The main deployment contains:

    Deployment
    Service
    HPA

The application Deployment uses the ECR image:

    892334471137.dkr.ecr.ap-south-1.amazonaws.com/hotstar-clone:<git-sha>

The Deployment is configured with:

    replicas: 2

Resource requests:

    CPU: 100m
    Memory: 128Mi

Resource limits:

    CPU: 500m
    Memory: 512Mi

The application container listens on:

    8080

Readiness and liveness probes check:

    /

This allows Kubernetes to determine whether the application is ready to receive traffic and whether the application is still healthy.

The Kubernetes deployment is intentionally stored in Git rather than being maintained manually on the cluster.

---

# Part 28 — Kubernetes Service and AWS Load Balancer

A Kubernetes Service was created to expose the Hotstar application.

Service:

    hotstar-clone

Type:

    LoadBalancer

The Service exposes:

    Port: 80
    Target Port: 8080

Traffic flow:

    Internet
       |
       v
    AWS Load Balancer
       |
       v
    Kubernetes Service :80
       |
       v
    Hotstar Pods :8080

The LoadBalancer hostname was obtained using:

    kubectl get svc hotstar-clone

or:

    kubectl get svc hotstar-clone \
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

The same LoadBalancer hostname is later used by Jenkins for:

    Post-deployment verification
    OWASP ZAP DAST

Therefore the application is validated through the same endpoint that external users access.

---

# Part 29 — Argo CD Installation

Argo CD was installed in the EKS cluster to implement GitOps-based continuous deployment.

Argo CD namespace:

    argocd

The official Argo CD installation manifest was applied to the cluster.

Verification:

    kubectl get pods -n argocd

The Argo CD components include:

    argocd-server
    argocd-repo-server
    argocd-application-controller
    argocd-dex-server
    argocd-redis
    argocd-applicationset-controller

The Argo CD server can be accessed locally using port forwarding:

    kubectl port-forward svc/argocd-server \
      -n argocd \
      8080:443

Argo CD provides the continuous delivery portion of the project.

Jenkins performs CI and updates Git.

Argo CD performs CD by synchronizing Git with Kubernetes.

---

# Part 30 — GitOps Application Configuration

An Argo CD Application named:

    hotstar-clone

was configured.

Repository:

    https://github.com/aakashrsethi39/hotstar-dev-secops.git

Path:

    k8s

Destination:

    https://kubernetes.default.svc

Namespace:

    default

Automated synchronization was enabled.

The GitOps flow is:

    Jenkins
       |
       | Update image in Git
       v
    GitHub GitOps Repository
       |
       | Detect change
       v
    Argo CD
       |
       | Sync
       v
    Kubernetes
       |
       v
    EKS

Argo CD was also configured for automated:

    Sync
    Prune
    Self-Heal

This means Git becomes the source of truth for the Kubernetes application configuration.

---

# Part 31 — Rolling Updates and Deployment Strategy

The Kubernetes Deployment was configured to use a RollingUpdate strategy.

Configuration:

    strategy:
      type: RollingUpdate
      rollingUpdate:
        maxUnavailable: 0
        maxSurge: 1

This means Kubernetes attempts to keep the existing application available while introducing the new version.

The deployment process is:

    Existing Pods
         |
         v
    Create New Pod
         |
         v
    New Pod Becomes Ready
         |
         v
    Remove Old Pod
         |
         v
    Continue Until Complete

With:

    maxUnavailable: 0

Kubernetes attempts not to intentionally take an existing available pod offline during the update.

With:

    maxSurge: 1

Kubernetes can temporarily create one additional pod during the rollout.

The deployment also uses pod anti-affinity preferences so Kubernetes attempts to distribute application replicas across different worker nodes.

---

# Part 32 — Metrics Server and Horizontal Pod Autoscaler

Metrics Server was installed in the EKS cluster.

Metrics Server provides CPU and memory usage metrics to Kubernetes.

Verification:

    kubectl top nodes

and:

    kubectl top pods

The Hotstar application uses a Horizontal Pod Autoscaler.

Configuration:

    Minimum replicas: 2
    Maximum replicas: 6

The HPA primarily scales the application based on CPU utilization.

The scaling flow is:

    CPU increases
        |
        v
    Metrics Server
        |
        v
    HPA
        |
        v
    Increase Replicas

When CPU decreases:

    CPU decreases
        |
        v
    HPA
        |
        v
    Reduce Replicas

The HPA was tested using CPU stress.

During the test the application successfully scaled:

    2 Pods
       ↓
    4 Pods
       ↓
    6 Pods

After the CPU stress stopped:

    6 Pods
       ↓
    2 Pods

The live HPA configuration also uses a scale-down stabilization window so that Kubernetes does not immediately remove replicas during short CPU fluctuations.

The HPA was verified using:

    kubectl get hpa

and:

    kubectl describe hpa hotstar-clone

---

# Part 33 — Prometheus, Grafana and Alertmanager

Monitoring was added using kube-prometheus-stack.

The Helm release was installed in:

    monitoring

The monitoring stack contains:

    Prometheus
    Grafana
    Alertmanager
    Prometheus Operator
    kube-state-metrics
    Node Exporter

The installation was performed using Helm.

The monitoring architecture is:

    Kubernetes
        |
        +------------------+
        |                  |
        v                  v
    kube-state-metrics   Node Exporter
        |                  |
        +--------+---------+
                 |
                 v
             Prometheus
                 |
                 v
              Grafana
                 |
                 v
              Alerts
                 |
                 v
             Email

The project initially experienced memory pressure on the smaller EKS worker nodes because the monitoring stack introduced additional workloads.

The worker node group was therefore scaled to four t3.small nodes.

The monitoring components were subsequently stable.

---

# Part 34 — Grafana Dashboard and Alerting

A custom Grafana dashboard was created:

    Hotstar EKS DevSecOps Monitoring

The dashboard contains five important panels.

## Running Pods

    count(
      kube_pod_status_phase{
        namespace="default",
        pod=~"hotstar-clone-.*",
        phase="Running"
      }
    )

## HPA Desired Replicas

    kube_horizontalpodautoscaler_status_desired_replicas{
      namespace="default",
      horizontalpodautoscaler="hotstar-clone"
    }

## HPA Current Replicas

    kube_horizontalpodautoscaler_status_current_replicas{
      namespace="default",
      horizontalpodautoscaler="hotstar-clone"
    }

## CPU Usage

    sum(
      rate(
        container_cpu_usage_seconds_total{
          namespace="default",
          pod=~"hotstar-clone-.*",
          container!="POD",
          container!=""
        }[5m]
      )
    )

## Memory Usage

    sum(
      container_memory_working_set_bytes{
        namespace="default",
        pod=~"hotstar-clone-.*",
        container!="POD",
        container!=""
      )
    ) / 1024 / 1024

The dashboard was provisioned using a Kubernetes ConfigMap so it does not depend only on Grafana's local database.

Dashboard file:

    k8s/monitoring/hotstar-dashboard.yaml

The Grafana Prometheus datasource uses the Prometheus datasource UID:

    prometheus

This ensured that the dashboard continued to display metrics correctly after Grafana pod recreation.

## Grafana Alerts

Three important alert conditions were configured.

### High CPU

CPU threshold:

    > 70%

Alert duration:

    1 minute

The alert evaluation flow is:

    Prometheus Query
          |
          v
       Reduce
          |
          v
      Threshold
          |
          v
       Alert

### Pod Failure

The alert detects when the number of running Hotstar pods falls below the expected minimum.

### HPA Maximum

The alert detects when the HPA reaches:

    6 replicas

This indicates that the application has reached its configured scaling limit.

## Email Notification

A Grafana contact point was created:

    Hotstar Email Alerts

Email notification was configured through Gmail SMTP.

The SMTP password is stored in a Kubernetes Secret and is not committed to Git.

The notification policy groups alerts by:

    grafana_folder
    alertname

The notification configuration includes:

    group_wait: 30s
    group_interval: 30s
    repeat_interval: 4h

The contact point was tested successfully.

A real High CPU alert was generated during the HPA stress test and the email notification was successfully received.

---

# Part 35 — OWASP ZAP DAST and Failure/Recovery Testing

OWASP ZAP was added as the Dynamic Application Security Testing stage.

The scan runs against the deployed application rather than the source code.

Jenkins obtains the Kubernetes LoadBalancer hostname:

    ALB_URL=$(kubectl get svc hotstar-clone \
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

ZAP then scans:

    http://${ALB_URL}

The Jenkins stage uses:

    /opt/zap/zap.sh \
      -cmd \
      -port 8090 \
      -quickurl "http://${ALB_URL}" \
      -quickout "$WORKSPACE/zap-report.json" \
      -quickprogress

The report is processed using `jq`.

The pipeline counts HIGH-risk findings.

Risk code:

    3 = High

The pipeline fails if:

    HIGH_COUNT > 0

The successful final scan produced:

    Risk 0 = 2
    Risk 2 = 2
    Risk 3 = 0

Therefore:

    High-risk findings: 0
    ZAP security gate passed.

The report contained informational and medium-risk findings but no HIGH-risk findings.

## Intentional GitOps Failure Test

A deployment failure was intentionally simulated by changing the Kubernetes image to:

    hotstar-clone:9999

The invalid image was committed to the GitOps repository.

Argo CD detected the Git change and synchronized it.

The new pod entered:

    ImagePullBackOff

The previous healthy pods remained available during the failed rollout.

This demonstrated that Kubernetes RollingUpdate does not automatically rewrite the desired image in Git.

The desired state remained:

    hotstar-clone:9999

Therefore the correct recovery method in the GitOps model was to fix Git.

The image was restored to the known-good image:

    hotstar-clone:f28c9cf

The fix was committed and pushed to Git.

Argo CD detected the new Git state and synchronized it.

The final state returned to:

    Synced
    Healthy

This demonstrated:

    GitOps Failure
        ↓
    Detect Failure
        ↓
    Correct Git
        ↓
    Argo CD Sync
        ↓
    Healthy Deployment

---

# Part 36 — Complete End-to-End Pipeline and Final Validation

The complete project workflow is now:

    Developer
        |
        | git push
        v
    GitHub Application Repository
        |
        | Webhook
        v
    Jenkins
        |
        +--> Checkout
        |
        +--> SonarQube SAST
        |
        +--> SonarQube Quality Gate
        |
        +--> Trivy Filesystem Scan
        |
        +--> Docker Build
        |
        +--> Trivy Image Scan
        |
        +--> Docker Scout
        |
        +--> ECR Login
        |
        +--> Push Image
        |
        v
    Amazon ECR
        |
        v
    Jenkins
        |
        | Update image SHA
        v
    GitHub GitOps Repository
        |
        v
    Argo CD
        |
        | Automated Sync
        v
    Amazon EKS
        |
        +--> Deployment
        |
        +--> Service
        |
        +--> HPA
        |
        +--> Health Checks
        |
        v
    Running Hotstar Application
        |
        +--> Prometheus
        |
        +--> Grafana
        |
        +--> Alerting
        |
        v
    OWASP ZAP
        |
        v
    Final Security Gate

## Final Security Validation

The final successful pipeline demonstrated:

    SonarQube
        → Quality Gate Passed

    Trivy Filesystem
        → Passed

    Trivy Image
        → 0 Vulnerabilities

    Docker Scout
        → 0 High/Critical Findings

    OWASP ZAP
        → 0 High-Risk Findings

## Final Kubernetes Validation

The application was successfully validated with:

    kubectl get nodes

    kubectl get pods

    kubectl get deployment

    kubectl get svc

    kubectl get hpa

    kubectl describe hpa hotstar-clone

    kubectl get rs

The final application state contained two healthy Hotstar pods during normal load.

The HPA successfully demonstrated scaling up to six replicas under CPU stress and scaling back down after the load stopped.

## Final GitOps Validation

Argo CD showed:

    Synced
    Healthy

The deployed image matched the image defined in the GitOps repository.

## Final Monitoring Validation

Grafana successfully displayed:

    Running Pods
    HPA Desired Replicas
    HPA Current Replicas
    CPU Usage
    Memory Usage

Grafana alerting successfully generated email notifications.

## Final DAST Validation

OWASP ZAP successfully scanned the live application.

Final result:

    High-risk findings = 0

The Jenkins security gate therefore passed.

## Final Project Architecture

    +----------------------+
    |       Developer      |
    +----------+-----------+
               |
               | Git Push
               v
    +----------------------+
    |       GitHub         |
    | Application Repo     |
    +----------+-----------+
               |
               | Webhook
               v
    +----------------------+
    |       Jenkins        |
    +----------+-----------+
               |
       +-------+-------+
       |       |       |
       v       v       v
    Sonar    Trivy   Docker
       |       |       |
       +-------+-------+
               |
               v
        Docker Scout
               |
               v
        +-------------+
        |     ECR     |
        +------+------+
               |
               v
       GitOps Repository
               |
               v
          +---------+
          | Argo CD |
          +----+----+
               |
               v
        +-------------+
        |    EKS      |
        +------+------+ 
               |
        +------+------+ 
        |      |      |
        v      v      v
     Pods    HPA   Service
        |             |
        |             v
        |        Load Balancer
        |
        +--------+
                 |
                 v
             Prometheus
                 |
                 v
              Grafana
                 |
                 v
              Alerts
                 |
                 v
              Email

        Running Application
                 |
                 v
             OWASP ZAP

## Final Project Highlights

The completed project demonstrates:

- AWS infrastructure provisioning using Terraform
- Modular Terraform architecture
- VPC and subnet design
- IAM roles and policies
- Amazon EKS
- Managed EKS node groups
- EC2-based Jenkins
- EC2-based SonarQube
- Jenkins Application Load Balancer
- GitHub webhook integration
- Docker containerization
- Non-root container execution
- SonarQube SAST
- SonarQube Quality Gate
- Trivy filesystem scanning
- Trivy container image scanning
- Docker Scout security scanning
- Amazon ECR
- Git SHA image tagging
- GitOps
- Argo CD
- Kubernetes Deployment
- RollingUpdate strategy
- Kubernetes Service
- AWS Load Balancer
- Readiness and liveness probes
- Metrics Server
- Horizontal Pod Autoscaler
- Prometheus
- Grafana
- Alertmanager/Grafana alerting
- Email notifications
- OWASP ZAP DAST
- Automated post-deployment verification
- Intentional failed deployment testing
- GitOps-based recovery
- End-to-end security gates
- Application monitoring and observability

## Final Result

The final implementation provides a complete DevSecOps pipeline where:

    Code
      ↓
    Security Analysis
      ↓
    Container Security
      ↓
    Image Registry
      ↓
    GitOps
      ↓
    Kubernetes Deployment
      ↓
    Automated Verification
      ↓
    Runtime Monitoring
      ↓
    Dynamic Security Testing

The project demonstrates how CI, security, CD, GitOps, Kubernetes, autoscaling, monitoring, and runtime security can be integrated into a single AWS-based DevSecOps platform.

---

