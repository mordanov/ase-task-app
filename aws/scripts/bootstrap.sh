#!/usr/bin/env bash
# Bootstrap script — deploys all CloudFormation stacks in dependency order
# and pushes initial Docker images to ECR.
#
# Usage: AWS_REGION=us-east-1 PROJECT_NAME=keycloak-app ENVIRONMENT=prod \
#          AWS_PROFILE=my-profile \
#          DOMAIN_NAME=app.example.com \
#          KEYCLOAK_ADMIN_PASSWORD=secret BACKEND_CLIENT_SECRET=secret \
#          bash aws/scripts/bootstrap.sh
#
# Prerequisites:
#   - AWS CLI v2 configured (aws configure or environment credentials)
#   - Docker running locally
#   - jq installed

set -euo pipefail

# ─── Config ────────────────────────────────────────────────────────────────────
PROJECT_NAME="${PROJECT_NAME:-keycloak-app}"
ENVIRONMENT="${ENVIRONMENT:-prod}"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_PROFILE="${AWS_PROFILE:-}"
DOMAIN_NAME="${DOMAIN_NAME:-}"
CFN_DIR="$(dirname "$0")/../cloudformation"

STACK_PREFIX="${PROJECT_NAME}-${ENVIRONMENT}"

log()  { echo -e "\033[1;34m[bootstrap]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[ok]\033[0m $*"; }
fail() { echo -e "\033[1;31m[error]\033[0m $*" >&2; exit 1; }

command -v aws  >/dev/null 2>&1 || fail "aws CLI not found"

# Inject --profile into every aws call when AWS_PROFILE is set
aws() { command aws ${AWS_PROFILE:+--profile "$AWS_PROFILE"} "$@"; }
command -v docker >/dev/null 2>&1 || fail "docker not found"
command -v jq  >/dev/null 2>&1 || fail "jq not found"
command -v npm >/dev/null 2>&1 || fail "npm not found"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
log "Account: $ACCOUNT_ID  Region: $AWS_REGION  Env: $ENVIRONMENT"

[[ -n "$DOMAIN_NAME" ]] || fail "DOMAIN_NAME env var is required (e.g. DOMAIN_NAME=app.example.com)"

# ─── Resolve Route53 Hosted Zone ID for DOMAIN_NAME ───────────────────────────
log "Looking up Route53 hosted zone for: $DOMAIN_NAME"

# Try exact match first, then strip one subdomain level to find the parent zone
_lookup_zone() {
  aws route53 list-hosted-zones \
    --query "HostedZones[?Name=='${1}.'].Id" \
    --output text 2>/dev/null | sed 's|/hostedzone/||'
}

HOSTED_ZONE_ID=$(_lookup_zone "$DOMAIN_NAME")
if [[ -z "$HOSTED_ZONE_ID" || "$HOSTED_ZONE_ID" == "None" ]]; then
  PARENT_DOMAIN="${DOMAIN_NAME#*.}"
  HOSTED_ZONE_ID=$(_lookup_zone "$PARENT_DOMAIN")
fi
[[ -n "$HOSTED_ZONE_ID" && "$HOSTED_ZONE_ID" != "None" ]] \
  || fail "Route53 hosted zone not found for '$DOMAIN_NAME'. Make sure the domain is added to Route53."
ok "Hosted zone: $HOSTED_ZONE_ID"

# ─── Helper: deploy or update a stack ──────────────────────────────────────────
deploy_stack() {
  local name="$1"
  local template="$2"
  shift 2
  local params=("$@")

  log "Deploying stack: $name"
  aws cloudformation deploy \
    --stack-name "$name" \
    --template-file "$template" \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset \
    --region "$AWS_REGION" \
    ${params[@]+"${params[@]}"} \
    && ok "Stack $name up-to-date" \
    || fail "Stack $name failed"
}

cfn_output() {
  local stack="$1"
  local key="$2"
  aws cloudformation describe-stacks \
    --stack-name "$stack" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='$key'].OutputValue" \
    --output text
}

# ─── 1. Network ────────────────────────────────────────────────────────────────
deploy_stack "${STACK_PREFIX}-network" "${CFN_DIR}/01-network.yml" \
  --parameter-overrides \
    ProjectName="$PROJECT_NAME" \
    Environment="$ENVIRONMENT"

# ─── 2. ECR ────────────────────────────────────────────────────────────────────
deploy_stack "${STACK_PREFIX}-ecr" "${CFN_DIR}/02-ecr.yml" \
  --parameter-overrides \
    ProjectName="$PROJECT_NAME" \
    Environment="$ENVIRONMENT"

BACKEND_REPO=$(cfn_output "${STACK_PREFIX}-ecr" "BackendRepositoryUri")
KEYCLOAK_REPO=$(cfn_output "${STACK_PREFIX}-ecr" "KeycloakRepositoryUri")

# ─── 3. Push initial Docker images ─────────────────────────────────────────────
log "Authenticating Docker with ECR"
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

log "Building and pushing backend image"
docker build --platform linux/amd64 \
  -f "$(dirname "$0")/../../backend/Dockerfile.prod" \
  -t "$BACKEND_REPO:latest" \
  "$(dirname "$0")/../../backend"
docker push "$BACKEND_REPO:latest"

log "Building and pushing Keycloak image"
KEYCLOAK_DIR="$(dirname "$0")/../../keycloak"
# Stash local realm, build with production template, always restore on exit
cp "$KEYCLOAK_DIR/realm-export.json" "$KEYCLOAK_DIR/realm-export.json.local.bak"
trap 'mv "$KEYCLOAK_DIR/realm-export.json.local.bak" "$KEYCLOAK_DIR/realm-export.json" 2>/dev/null || true' EXIT
cp "$KEYCLOAK_DIR/realm-export-template.json" "$KEYCLOAK_DIR/realm-export.json"
docker build --platform linux/amd64 \
  -f "$KEYCLOAK_DIR/Dockerfile" \
  -t "$KEYCLOAK_REPO:latest" \
  "$KEYCLOAK_DIR"
docker push "$KEYCLOAK_REPO:latest"
mv "$KEYCLOAK_DIR/realm-export.json.local.bak" "$KEYCLOAK_DIR/realm-export.json"
trap - EXIT

# ─── 4. Database ───────────────────────────────────────────────────────────────
deploy_stack "${STACK_PREFIX}-database" "${CFN_DIR}/03-database.yml" \
  --parameter-overrides \
    ProjectName="$PROJECT_NAME" \
    Environment="$ENVIRONMENT"

# ─── 5. ECS Cluster + ALB ──────────────────────────────────────────────────────
deploy_stack "${STACK_PREFIX}-cluster" "${CFN_DIR}/04-cluster.yml" \
  --parameter-overrides \
    ProjectName="$PROJECT_NAME" \
    Environment="$ENVIRONMENT"

# ─── 6. ACM Certificate (must be in us-east-1 for CloudFront) ─────────────────
log "Deploying ACM certificate stack to us-east-1 (DNS validation via Route53)"
command aws ${AWS_PROFILE:+--profile "$AWS_PROFILE"} cloudformation deploy \
  --stack-name "${STACK_PREFIX}-certificate" \
  --template-file "${CFN_DIR}/12-certificate.yml" \
  --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset \
  --region us-east-1 \
  --parameter-overrides \
    ProjectName="$PROJECT_NAME" \
    Environment="$ENVIRONMENT" \
    DomainName="$DOMAIN_NAME" \
    HostedZoneId="$HOSTED_ZONE_ID" \
  && ok "Certificate stack up-to-date" \
  || fail "Certificate stack failed"

CERT_ARN=$(command aws ${AWS_PROFILE:+--profile "$AWS_PROFILE"} cloudformation describe-stacks \
  --stack-name "${STACK_PREFIX}-certificate" \
  --region us-east-1 \
  --query "Stacks[0].Outputs[?OutputKey=='CertificateArn'].OutputValue" \
  --output text)
ok "Certificate ARN: $CERT_ARN"

# ─── 7. CloudFront + S3 Frontend ───────────────────────────────────────────────
deploy_stack "${STACK_PREFIX}-frontend" "${CFN_DIR}/07-frontend.yml" \
  --parameter-overrides \
    ProjectName="$PROJECT_NAME" \
    Environment="$ENVIRONMENT" \
    CustomDomain="$DOMAIN_NAME" \
    AcmCertificateArn="$CERT_ARN" \
    HostedZoneId="$HOSTED_ZONE_ID"

APP_URL="https://${DOMAIN_NAME}"
log "App URL: $APP_URL"

FRONTEND_BUCKET=$(cfn_output "${STACK_PREFIX}-frontend" "FrontendBucketName")
CLOUDFRONT_DISTRIBUTION_ID=$(cfn_output "${STACK_PREFIX}-frontend" "CloudFrontDistributionId")

log "Building frontend for ${APP_URL}"
FRONTEND_DIR="$(dirname "$0")/../../frontend"
if [[ -f "$FRONTEND_DIR/package-lock.json" ]]; then
  npm --prefix "$FRONTEND_DIR" ci
else
  npm --prefix "$FRONTEND_DIR" install
fi

VITE_KEYCLOAK_URL="$APP_URL" \
VITE_KEYCLOAK_REALM="app-realm" \
VITE_KEYCLOAK_CLIENT_ID="frontend-client" \
VITE_API_URL="$APP_URL" \
  npm --prefix "$FRONTEND_DIR" run build

log "Uploading frontend to s3://${FRONTEND_BUCKET}"
aws s3 sync "$FRONTEND_DIR/dist" "s3://${FRONTEND_BUCKET}" \
  --delete \
  --exclude "index.html" \
  --cache-control "public,max-age=31536000,immutable"

aws s3 cp "$FRONTEND_DIR/dist/index.html" "s3://${FRONTEND_BUCKET}/index.html" \
  --cache-control "no-cache,no-store,must-revalidate"

log "Invalidating CloudFront cache"
aws cloudfront create-invalidation \
  --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
  --paths "/*" >/dev/null
ok "Frontend published"

# ─── 7. Keycloak service ───────────────────────────────────────────────────────
[[ -n "${KEYCLOAK_ADMIN_PASSWORD:-}" ]] || fail "KEYCLOAK_ADMIN_PASSWORD env var is required"
[[ -n "${BACKEND_CLIENT_SECRET:-}" ]]  || fail "BACKEND_CLIENT_SECRET env var is required"

# Extract hostname from full URL (e.g., https://aleksandr-mordanov.click → aleksandr-mordanov.click)
FRONTEND_HOSTNAME=$(echo "$APP_URL" | sed -E 's|https?://||')

deploy_stack "${STACK_PREFIX}-keycloak" "${CFN_DIR}/05-keycloak.yml" \
  --parameter-overrides \
    ProjectName="$PROJECT_NAME" \
    Environment="$ENVIRONMENT" \
    FrontendUrl="$APP_URL" \
    FrontendHostname="$FRONTEND_HOSTNAME" \
    KeycloakAdminPassword="$KEYCLOAK_ADMIN_PASSWORD" \
    BackendClientSecret="$BACKEND_CLIENT_SECRET" \
    GoogleClientId="${GOOGLE_CLIENT_ID:-}" \
    GoogleClientSecret="${GOOGLE_CLIENT_SECRET:-}" \
    GithubClientId="${GITHUB_CLIENT_ID:-}" \
    GithubClientSecret="${GITHUB_CLIENT_SECRET:-}" \
    AzureApplicationId="${AZURE_APPLICATION_ID:-}" \
    AzureClientSecret="${AZURE_CLIENT_SECRET:-}"

# ─── 8. Backend service ────────────────────────────────────────────────────────
deploy_stack "${STACK_PREFIX}-backend" "${CFN_DIR}/06-backend.yml" \
  --parameter-overrides \
    ProjectName="$PROJECT_NAME" \
    Environment="$ENVIRONMENT" \
    FrontendUrl="$APP_URL" \
    BackendClientSecret="$BACKEND_CLIENT_SECRET"

# ─── 9. Cache (ElastiCache Redis) ──────────────────────────────────────────────
deploy_stack "${STACK_PREFIX}-cache" "${CFN_DIR}/11-cache.yml" \
  --parameter-overrides \
    ProjectName="$PROJECT_NAME" \
    Environment="$ENVIRONMENT"

# ─── 10. Spark (EMR Serverless) ────────────────────────────────────────────────
deploy_stack "${STACK_PREFIX}-spark" "${CFN_DIR}/10-spark.yml" \
  --parameter-overrides \
    ProjectName="$PROJECT_NAME" \
    Environment="$ENVIRONMENT"

# ─── 11. App service (DesiredCount=0 until image is pushed) ────────────────────
deploy_stack "${STACK_PREFIX}-app" "${CFN_DIR}/09-app.yml" \
  --parameter-overrides \
    ProjectName="$PROJECT_NAME" \
    Environment="$ENVIRONMENT"

# ─── 12. CI/CD IAM (run once, not environment-specific) ────────────────────────
if [[ -n "${GITHUB_ORG:-}" && -n "${GITHUB_REPO:-}" ]]; then
  deploy_stack "${PROJECT_NAME}-cicd" "${CFN_DIR}/08-cicd.yml" \
    --parameter-overrides \
      ProjectName="$PROJECT_NAME" \
      GitHubOrg="$GITHUB_ORG" \
      GitHubRepo="$GITHUB_REPO"

  GITHUB_ROLE=$(cfn_output "${PROJECT_NAME}-cicd" "GitHubActionsRoleArn")
  ok "GitHub Actions IAM role: $GITHUB_ROLE"
else
  log "Skipping CI/CD stack (set GITHUB_ORG and GITHUB_REPO to create it)"
fi

# ─── Summary ───────────────────────────────────────────────────────────────────
echo ""
ok "Bootstrap complete!"
echo ""
echo "  App URL:          $APP_URL"
echo "  Keycloak admin:   $APP_URL/realms/app-realm (use Keycloak admin console for realm management)"
echo ""
echo "Next steps:"
echo "  1. Add AWS_ROLE_ARN secret to GitHub repo"
echo "  2. Add AWS_REGION variable to GitHub repo (value: $AWS_REGION)"
echo "  3. Update OAuth provider redirect URIs at the providers' consoles to allow: $APP_URL"
echo "  4. Push to main branch to trigger the GitHub Actions deployment pipeline"
