# AWS Deployment Guide

## Architecture

```
Users → CloudFront → (path routing)
                 ├─ /api/*        → ALB → ECS Fargate (FastAPI backend)
                 ├─ /realms/*     → ALB → ECS Fargate (Keycloak)
                 ├─ /resources/*  → ALB → ECS Fargate (Keycloak themes)
                 └─ /*            → S3  (React SPA)

ECS Fargate (private subnets, NAT for outbound)
     ├─ Backend:  auto-scaling 0→50 tasks, 0.5 vCPU / 1 GB each
     └─ Keycloak: auto-scaling 1→3  tasks, 1 vCPU  / 2 GB each

RDS PostgreSQL 16 (private subnets, encrypted, automated backups)

Secrets Manager  — DB credentials, Keycloak secrets, origin-verify token
```

Security highlights:
- ALB rejects requests missing the `X-Origin-Verify` header (only CloudFront knows the value)
- ECS tasks run in private subnets with no public IP
- RDS accepts connections only from ECS security group
- IAM uses OIDC for GitHub Actions — no static AWS credentials stored

---

## Prerequisites

| Tool | Version |
|------|---------|
| AWS CLI | v2 |
| Docker | 24+ |
| jq | 1.6+ |
| Node.js | 20 |

Your AWS user/role needs CloudFormation, IAM, ECR, ECS, RDS, S3, CloudFront, and Secrets Manager permissions.

---

## First-time bootstrap

```bash
export AWS_REGION=us-east-1
export PROJECT_NAME=keycloak-app
export ENVIRONMENT=prod

# Optional — needed to create the GitHub Actions IAM role
export GITHUB_ORG=your-github-org
export GITHUB_REPO=keycloak-app

# OAuth provider credentials (from your .env)
export GOOGLE_CLIENT_ID=...
export GOOGLE_CLIENT_SECRET=...
export GITHUB_CLIENT_ID=...
export GITHUB_CLIENT_SECRET=...
export AZURE_APPLICATION_ID=...
export AZURE_CLIENT_SECRET=...

bash aws/scripts/bootstrap.sh
```

The script will:
1. Deploy network, ECR, RDS, ECS cluster, ALB
2. Build and push initial Docker images
3. Prompt for Keycloak admin password and backend-client secret
4. Deploy Keycloak and backend ECS services
5. Deploy S3 bucket and CloudFront distribution
6. Print the App URL and next steps

**RDS takes 5–10 minutes to provision. Keycloak takes 2–3 minutes to start after that.**

---

## CloudFormation stacks

| Stack | File | Description |
|-------|------|-------------|
| `*-network` | `01-network.yml` | VPC, subnets, NAT, security groups |
| `*-ecr` | `02-ecr.yml` | ECR repositories |
| `*-database` | `03-database.yml` | RDS PostgreSQL + Secrets Manager |
| `*-cluster` | `04-cluster.yml` | ECS cluster, ALB, IAM roles |
| `*-keycloak` | `05-keycloak.yml` | Keycloak Fargate service + auto-scaling |
| `*-backend` | `06-backend.yml` | FastAPI Fargate service + auto-scaling |
| `*-frontend` | `07-frontend.yml` | S3 bucket + CloudFront distribution |
| `keycloak-app-cicd` | `08-cicd.yml` | GitHub OIDC provider + IAM role |

Deploy order must match the table above (later stacks import outputs from earlier ones).

### Re-deploying a single stack

```bash
aws cloudformation deploy \
  --stack-name keycloak-app-prod-backend \
  --template-file aws/cloudformation/06-backend.yml \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    ProjectName=keycloak-app \
    Environment=prod \
    FrontendUrl=https://d1234.cloudfront.net \
    BackendClientSecret=<your-secret>
```

---

## GitHub Actions setup

After the bootstrap script prints the GitHub Actions IAM role ARN, add these to your repository:

**Secrets** (`Settings → Secrets → Actions`):
- `AWS_ROLE_ARN` — IAM role ARN from the `08-cicd` stack output

**Variables** (`Settings → Variables → Actions`):
- `AWS_REGION` — e.g. `us-east-1`

The `deploy.yml` workflow runs on every push to `main` and:
1. Builds backend and Keycloak images in parallel → pushes to ECR
2. Builds the React frontend with the correct CloudFront URL baked in → uploads to S3
3. Invalidates the CloudFront cache
4. Rolls out new ECS task definitions for backend and Keycloak

---

## Auto-scaling

### Backend (FastAPI)
- **Min:** 1 (set to `0` for scale-to-zero; first request after idle adds ~30s)
- **Max:** 50
- Scales up when CPU > 60% or ALB requests > 1000/target
- Scale-out cooldown: 30s, scale-in cooldown: 120s

### Keycloak
- **Min:** 1 (must always be available for auth)
- **Max:** 3
- Scales up when CPU > 65% or memory > 70%
- Sticky sessions (lb_cookie) keep users on the same instance

To change capacities, update the stack parameters:
```bash
aws cloudformation deploy \
  --stack-name keycloak-app-prod-backend \
  --template-file aws/cloudformation/06-backend.yml \
  --parameter-overrides MinCapacity=0 MaxCapacity=100 ...
```

---

## Local development (unchanged)

```bash
docker compose up -d
```

The local setup is completely independent. It uses the original `realm-export.json` with `localhost:3001` redirect URIs, a local PostgreSQL container, and Keycloak running in dev mode.

---

## Secrets reference

All secrets are stored in AWS Secrets Manager under `/<project>/<env>/`:

| Path | Contents |
|------|---------|
| `/keycloak-app/prod/db-credentials` | `username`, `password` (auto-generated by RDS) |
| `/keycloak-app/prod/keycloak` | `admin_password`, `backend_client_secret`, OAuth IDs/secrets |
| `/keycloak-app/prod/backend` | `keycloak_client_secret` |
| `/keycloak-app/prod/cloudfront-origin-secret` | `value` (auto-generated, used in X-Origin-Verify) |

To rotate the backend-client secret:
1. Update `/keycloak-app/prod/keycloak` and `/keycloak-app/prod/backend` in Secrets Manager
2. Update the client secret in Keycloak admin console
3. Force a new ECS deployment: `aws ecs update-service --force-new-deployment ...`

---

## Costs (rough estimate, us-east-1)

| Resource | ~Monthly |
|----------|---------|
| RDS db.t3.micro (1 AZ) | $15 |
| NAT Gateway | $35 |
| ECS Fargate 1×backend + 1×keycloak (24/7) | $30 |
| CloudFront (1TB/mo transfer) | $85 |
| ALB | $20 |
| **Total (idle/low traffic)** | **~$185/mo** |

Scale-to-zero the backend (`MinCapacity=0`) saves ~$8/mo.
Enable Multi-AZ on RDS (`MultiAZ=true`) adds ~$15/mo.
