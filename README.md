# BusinessConnect — ECS vs EKS Deployment Guide

> **Scenario**: ShopNow DevOps benchmark — deploying the same multi-tier application to **Amazon ECS (Fargate)** and **Amazon EKS**, comparing orchestration models for service discovery, load balancing, and resiliency.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Repository Layout](#2-repository-layout)
3. [Prerequisites](#3-prerequisites)
4. [Local Development (docker-compose)](#4-local-development)
5. [Infrastructure Provisioning (Terraform)](#5-infrastructure-provisioning)
6. [Build & Push Images to ECR](#6-build--push-images-to-ecr)
7. [ECS (Fargate) Deployment](#7-ecs-fargate-deployment)
8. [EKS Deployment](#8-eks-deployment)
9. [Resiliency Testing](#9-resiliency-testing)
10. [ECS vs EKS Benchmark Comparison](#10-ecs-vs-eks-benchmark-comparison)
11. [Cleanup](#11-cleanup)

---

## 1. Architecture Overview

```
Internet
   │
   ▼
[Application Load Balancer]   (public, port 80)
   │
   ▼ port 3000
[frontend]  ←── Nginx SPA + /api/* proxy
   │
   │ ${GATEWAY_URL}  (env var at container start)
   ▼ port 4000
[gateway]   ←── Express.js reverse proxy
   │
   ├──► [auth-service    :4001]
   ├──► [business-service:4002]
   ├──► [review-service  :4003]
   └──► [inquiry-service :4004]
              │
        ┌─────┴──────┐
        ▼            ▼
   [postgres:5432] [redis:6379]
```

### Service Ports

| Service          | Port | Role                                      |
|------------------|------|-------------------------------------------|
| frontend         | 3000 | React SPA served by Nginx                 |
| gateway          | 4000 | Reverse proxy to all backend services     |
| auth-service     | 4001 | Authentication (better-auth + PostgreSQL) |
| business-service | 4002 | Businesses, jobs, events, services, etc.  |
| review-service   | 4003 | Reviews                                   |
| inquiry-service  | 4004 | Inquiries + mailer                        |
| postgres         | 5432 | Primary database                          |
| redis            | 6379 | Session store / cache                     |

### Service Discovery

| Platform | Mechanism          | Example                                        |
|----------|--------------------|------------------------------------------------|
| ECS      | AWS Cloud Map DNS  | `http://auth-service.businessconnect.local:4001` |
| EKS      | Kubernetes DNS     | `http://auth-service:4001`                     |
| Local    | Docker Compose DNS | `http://auth-service:4001`                     |

---

## 2. Repository Layout

```
businessConnect/
├── docker-compose.yml          # Local dev stack
├── init.sql                    # DB seed (mounted into postgres)
│
├── frontend/                   # React + Vite SPA
│   ├── Dockerfile              # Multi-stage: build → nginx:alpine
│   └── nginx.conf              # Nginx template; proxies /api/* via GATEWAY_URL
│
├── services/
│   ├── auth-service/           # Node.js (better-auth)
│   ├── business-service/       # Node.js (Express)
│   ├── review-service/         # Node.js (Express)
│   ├── inquiry-service/        # Node.js (Express + nodemailer)
│   └── gateway/                # Node.js (http-proxy-middleware)
│
├── migrate/                    # Drizzle migration runner
│
├── terraform/                  # AWS IaC
│   ├── providers.tf
│   ├── variables.tf
│   ├── terraform.tfvars.example
│   ├── outputs.tf
│   ├── vpc.tf                  # VPC, subnets, IGW, NAT, route tables
│   ├── security_groups.tf      # Granular SGs per service tier
│   ├── iam.tf                  # ECS execution/task roles, EKS cluster/node roles
│   ├── ecr.tf                  # ECR repos for all 6 images
│   ├── ecs.tf                  # ECS cluster, Cloud Map, ALB, task defs, services
│   └── eks.tf                  # EKS cluster, managed node group, addons
│
├── k8s/                        # Kubernetes manifests (applied to EKS)
│   ├── 00-namespace.yaml
│   ├── 01-configmap.yaml
│   ├── 02-secrets.yaml
│   ├── postgres/               # PVC + Deployment + Service
│   ├── redis/                  # Deployment + Service
│   ├── auth-service/
│   ├── business-service/
│   ├── review-service/
│   ├── inquiry-service/
│   ├── gateway/
│   ├── frontend/
│   └── ingress/                # AWS ALB Ingress (requires LB Controller)
│
└── scripts/
    ├── 01-build-push.sh        # Build & push all images to ECR
    ├── 02-deploy-eks.sh        # Apply K8s manifests to EKS
    └── 03-resiliency-test.sh   # Kill a pod/task and watch recovery
```

---

## 3. Prerequisites

| Tool          | Version  | Purpose                        |
|---------------|----------|--------------------------------|
| Docker        | ≥ 24     | Build & run containers         |
| AWS CLI       | v2       | ECR auth, ECS/EKS control      |
| Terraform     | ≥ 1.6    | Provision AWS infrastructure   |
| kubectl       | ≥ 1.29   | Manage EKS cluster             |
| Node.js       | ≥ 20     | (optional) run services locally|

Configure AWS credentials:
```bash
aws configure
# or
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_REGION=us-east-1
```

---

## 4. Local Development

Verify the full stack runs locally with a single command:

```bash
cd businessConnect
docker compose up --build
```

| URL                        | Service           |
|----------------------------|-------------------|
| http://localhost:3000      | Frontend (React)  |
| http://localhost:4000      | Gateway           |
| http://localhost:4000/health | Gateway health  |

To run migrations separately:
```bash
docker compose run --rm migrate
```

Stop and clean up:
```bash
docker compose down -v
```

---

## 5. Infrastructure Provisioning

All AWS resources (VPC, security groups, IAM roles, ECR, ECS cluster + services, EKS cluster + node group) are managed by Terraform.

### 5.1 Configure variables

```bash
cd businessConnect/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set better_auth_secret, db_password, aws_region, etc.
```

### 5.2 Initialize and apply

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Provisioning takes approximately **15–25 minutes** (EKS cluster creation dominates).

### 5.3 What gets created

**Shared Network:**
- VPC `10.0.0.0/16` — 2 public subnets (ALB), 2 private subnets (services/nodes)
- Internet Gateway + NAT Gateway
- Route tables

**Security Groups (per service tier):**
- `sg-alb` — internet → ALB
- `sg-frontend` — ALB → frontend (3000)
- `sg-gateway` — frontend → gateway (4000)
- `sg-auth` — gateway + services → auth (4001)
- `sg-backend-services` — gateway → business/review/inquiry (4002–4004)
- `sg-redis` — services → redis (6379)
- `sg-postgres` — services → postgres (5432)
- `sg-eks-nodes` — EKS worker nodes

**ECS:**
- Cluster `businessconnect-ecs` (Fargate)
- Cloud Map namespace `businessconnect.local`
- 8 ECS services (postgres, redis, auth, business, review, inquiry, gateway, frontend)
- External ALB → frontend ECS service

**EKS:**
- Cluster `businessconnect-eks` (v1.31)
- Managed node group: 2×t3.medium in private subnets
- Addons: vpc-cni, coredns, kube-proxy, aws-ebs-csi-driver

**ECR:** 6 repositories (one per custom image)

### 5.4 Retrieve outputs

```bash
terraform output alb_dns_name           # ECS entry point
terraform output eks_kubeconfig_command # configure kubectl for EKS
terraform output ecr_repository_urls   # image URIs for scripts
```

---

## 6. Build & Push Images to ECR

```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

cd businessConnect
./scripts/01-build-push.sh          # pushes tag 'latest'
./scripts/01-build-push.sh v1.0.0   # push a versioned tag
```

The script:
1. Authenticates Docker to ECR
2. Builds each service image for `linux/amd64` (Fargate + EKS compatible)
3. Pushes to the ECR repositories created by Terraform

---

## 7. ECS (Fargate) Deployment

ECS resources are provisioned automatically by Terraform. After `terraform apply`:

### 7.1 Verify services are running

```bash
aws ecs list-services --cluster businessconnect-ecs
aws ecs describe-services \
  --cluster businessconnect-ecs \
  --services businessconnect-frontend businessconnect-gateway
```

### 7.2 Service discovery with Cloud Map

Each ECS service registers its task IP with Cloud Map under the `businessconnect.local` private DNS namespace:

```
postgres.businessconnect.local:5432
redis.businessconnect.local:6379
auth-service.businessconnect.local:4001
business-service.businessconnect.local:4002
review-service.businessconnect.local:4003
inquiry-service.businessconnect.local:4004
gateway.businessconnect.local:4000
```

The gateway task definition sets environment variables using these Cloud Map DNS names. The frontend Nginx container replaces `${GATEWAY_URL}` with `http://gateway.businessconnect.local:4000` at startup via `envsubst`.

### 7.3 Access the application

```bash
# Get the ALB DNS name
ALB=$(terraform -chdir=terraform output -raw alb_dns_name)
echo "App URL: http://${ALB}"
curl "http://${ALB}/health" || true
```

### 7.4 Force a new deployment (after image update)

```bash
aws ecs update-service \
  --cluster businessconnect-ecs \
  --service businessconnect-frontend \
  --force-new-deployment
```

### 7.5 View logs in CloudWatch

```bash
aws logs tail /ecs/businessconnect/gateway --follow
aws logs tail /ecs/businessconnect/auth-service --follow
```

---

## 8. EKS Deployment

### 8.1 Configure kubectl

```bash
$(terraform -chdir=terraform output -raw eks_kubeconfig_command)
# or manually:
aws eks update-kubeconfig --region us-east-1 --name businessconnect-eks
```

### 8.2 Install AWS Load Balancer Controller (required for Ingress)

```bash
# Associate OIDC provider
CLUSTER=businessconnect-eks
REGION=us-east-1
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

eksctl utils associate-iam-oidc-provider \
  --cluster "${CLUSTER}" --region "${REGION}" --approve

# Create IAM policy
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.8.1/docs/install/iam_policy.json
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

# Install via Helm
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="${CLUSTER}" \
  --set serviceAccount.create=true \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::${ACCOUNT}:role/AWSLoadBalancerControllerRole"
```

### 8.3 Deploy the application

```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

./scripts/02-deploy-eks.sh          # uses tag 'latest'
./scripts/02-deploy-eks.sh v1.0.0   # use a specific tag
```

The script automatically substitutes `<ACCOUNT_ID>` and `<REGION>` placeholders in the manifest image fields.

### 8.4 Verify the deployment

```bash
kubectl get all -n businessconnect
kubectl get ingress -n businessconnect
```

Wait for the Ingress to show an ALB hostname (60–90 s), then open it in a browser.

### 8.5 Kubernetes service discovery

Within the `businessconnect` namespace, services resolve by name:

| From              | Calls                           | Kubernetes DNS                  |
|-------------------|---------------------------------|---------------------------------|
| gateway           | auth-service:4001               | auth-service.businessconnect    |
| gateway           | business-service:4002           | business-service.businessconnect|
| auth-service      | postgres:5432, redis:6379       | postgres.businessconnect        |
| frontend (Nginx)  | gateway-service:4000            | gateway-service.businessconnect |

CoreDNS (installed as EKS addon) handles all resolution automatically.

---

## 9. Resiliency Testing

### 9.1 EKS — Kill a pod

```bash
# Kill the gateway pod and watch Kubernetes replace it automatically
./scripts/03-resiliency-test.sh eks gateway

# Or manually:
POD=$(kubectl get pods -n businessconnect -l app=gateway -o name | head -1)
kubectl delete "${POD}" -n businessconnect --grace-period=0 --force

# Watch replacement
kubectl get pods -n businessconnect -l app=gateway -w
```

**What happens:**
1. Pod is deleted → Kubernetes detects the desired count (2) is not met
2. ReplicaSet controller immediately schedules a new pod
3. New pod starts, passes readiness probe, and joins the service endpoints
4. Total recovery time: **15–30 seconds**

### 9.2 ECS — Kill a task

```bash
# Kill a running task in the gateway service
export ECS_CLUSTER=businessconnect-ecs
./scripts/03-resiliency-test.sh ecs gateway

# Or manually:
TASK=$(aws ecs list-tasks --cluster businessconnect-ecs \
       --service-name businessconnect-gateway \
       --query 'taskArns[0]' --output text)
aws ecs stop-task --cluster businessconnect-ecs --task "${TASK}" \
    --reason "Resiliency test"

# Watch ECS launch a replacement
watch -n 5 "aws ecs describe-services \
  --cluster businessconnect-ecs \
  --services businessconnect-gateway \
  --query 'services[0].{Running:runningCount,Pending:pendingCount,Desired:desiredCount}'"
```

**What happens:**
1. Task stops → ECS scheduler detects running count < desired count (2)
2. ECS provisions a new Fargate task (pulls image, attaches ENI)
3. Task registers with Cloud Map and ALB target group after health checks pass
4. Total recovery time: **30–60 seconds** (Fargate cold start is slower than K8s pod restart)

---

## 10. ECS vs EKS Benchmark Comparison

| Dimension               | ECS (Fargate)                             | EKS (Managed Nodes)                       |
|-------------------------|-------------------------------------------|-------------------------------------------|
| **Setup complexity**    | Low — Terraform provisions everything     | Medium — node groups + addons + RBAC      |
| **Control plane**       | Fully managed by AWS                      | Managed by AWS, more configurable         |
| **Compute model**       | Serverless (Fargate) — no EC2 to manage   | EC2 nodes — you manage capacity           |
| **Service discovery**   | Cloud Map (DNS A records, MULTIVALUE)      | CoreDNS built-in (Kubernetes Services)    |
| **Load balancing**      | ALB → ECS service (IP target type)        | ALB via K8s Ingress + LB Controller       |
| **Secrets management**  | AWS Secrets Manager / SSM param store     | K8s Secrets / External Secrets Operator   |
| **Scaling**             | ECS Service Auto Scaling                  | HPA (CPU/memory) + Cluster Autoscaler     |
| **Persistent storage**  | EFS (complex) — better to use RDS         | PVC → EBS (gp2/gp3), straightforward     |
| **Cold start time**     | ~15–30 s (Fargate ENI allocation)         | ~5–15 s (pod start on warm node)          |
| **Recovery time**       | ~45–60 s after task kill                  | ~15–30 s after pod kill                  |
| **Operational overhead**| Low — no cluster nodes to patch           | Higher — node AMIs, CSI drivers, addons   |
| **Cost model**          | Pay per vCPU/GB-s (per task)              | Pay per EC2 instance (even when idle)     |
| **Portability**         | AWS-only                                  | Kubernetes standard — portable            |
| **Debugging**           | CloudWatch Logs, ECS Exec                 | kubectl logs/exec, any K8s tooling        |
| **Best for**            | Teams wanting minimal ops overhead        | Teams needing fine-grained control        |

### Verdict

- Choose **ECS Fargate** when: you want simplicity, predictable cost scaling from zero, and AWS-managed infrastructure.
- Choose **EKS** when: you need Kubernetes ecosystem tooling (Helm, Argo CD, Istio), cross-cloud portability, or advanced scheduling policies.

---

## 11. Cleanup

Destroy all AWS resources to avoid ongoing charges:

```bash
# 1. Delete EKS resources (prevents Terraform from timing out on VPC deletion)
kubectl delete namespace businessconnect --ignore-not-found

# 2. Destroy all Terraform-managed resources
cd terraform
terraform destroy -auto-approve

# 3. ECR images are preserved by default (force_delete = true in ecr.tf handles this)
```

> **Warning:** `terraform destroy` removes the VPC, ECS cluster, EKS cluster, ALB, ECR repos, and all associated IAM roles. This is irreversible.
