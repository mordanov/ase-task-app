#!/usr/bin/env bash
# Teardown script — deletes all CloudFormation stacks in reverse dependency order.
#
# Usage: AWS_REGION=us-east-1 PROJECT_NAME=keycloak-app ENVIRONMENT=prod \
#          AWS_PROFILE=my-profile bash aws/scripts/teardown.sh
#
# Notes:
#   - Aurora cluster will produce a final snapshot before deletion (DeletionPolicy: Snapshot).
#     Delete the snapshot manually in the RDS console if you don't need it.
#   - Secrets Manager secrets enter a 7-day recovery window; force-delete with --force-delete-without-recovery if needed.
#   - The CI/CD stack (08-cicd.yml) is not environment-specific and is only deleted
#     when no other environments share it (prompted below).

set -euo pipefail

# ─── Config ────────────────────────────────────────────────────────────────────
PROJECT_NAME="${PROJECT_NAME:-keycloak-app}"
ENVIRONMENT="${ENVIRONMENT:-prod}"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_PROFILE="${AWS_PROFILE:-}"

STACK_PREFIX="${PROJECT_NAME}-${ENVIRONMENT}"

log()  { echo -e "\033[1;34m[teardown]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[ok]\033[0m $*"; }
warn() { echo -e "\033[1;33m[warn]\033[0m $*"; }
fail() { echo -e "\033[1;31m[error]\033[0m $*" >&2; exit 1; }

command -v aws >/dev/null 2>&1 || fail "aws CLI not found"

# Inject --profile into every aws call when AWS_PROFILE is set
aws() { command aws ${AWS_PROFILE:+--profile "$AWS_PROFILE"} "$@"; }
command -v jq  >/dev/null 2>&1 || fail "jq not found"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
log "Account: $ACCOUNT_ID  Region: $AWS_REGION  Env: $ENVIRONMENT"
echo ""
warn "This will PERMANENTLY DELETE all infrastructure for: ${STACK_PREFIX}"
warn "Aurora will create a final snapshot. S3 and ECR contents will be erased."
echo ""
read -rp "Type the environment name '${ENVIRONMENT}' to confirm: " CONFIRM
[[ "$CONFIRM" == "$ENVIRONMENT" ]] || { log "Aborted."; exit 0; }

# ─── Helpers ───────────────────────────────────────────────────────────────────
stack_exists() {
  local status
  status=$(aws cloudformation describe-stacks \
    --stack-name "$1" \
    --region "$AWS_REGION" \
    --query 'Stacks[0].StackStatus' \
    --output text 2>/dev/null) || return 1
  [[ "$status" != "DELETE_COMPLETE" ]]
}

cfn_output() {
  aws cloudformation describe-stacks \
    --stack-name "$1" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue" \
    --output text 2>/dev/null || true
}

delete_stack() {
  local name="$1"
  if ! stack_exists "$name"; then
    warn "Stack $name not found or already deleted — skipping"
    return
  fi
  log "Deleting stack: $name"
  aws cloudformation delete-stack --stack-name "$name" --region "$AWS_REGION"
  if ! aws cloudformation wait stack-delete-complete \
      --stack-name "$name" --region "$AWS_REGION"; then
    # Surface the reason for DELETE_FAILED
    local reason
    reason=$(aws cloudformation describe-stack-events \
      --stack-name "$name" --region "$AWS_REGION" \
      --query 'StackEvents[?ResourceStatus==`DELETE_FAILED`].ResourceStatusReason' \
      --output text 2>/dev/null | head -3)
    fail "Stack $name deletion failed: $reason"
  fi
  ok "Stack $name deleted"
}

empty_s3_bucket() {
  local bucket="$1"
  log "Emptying S3 bucket: $bucket"

  # Remove all current objects
  aws s3 rm "s3://${bucket}" --recursive --region "$AWS_REGION" --quiet 2>/dev/null || true

  # Remove all versioned objects and delete markers (if versioning was enabled)
  while true; do
    local batch
    batch=$(aws s3api list-object-versions \
      --bucket "$bucket" \
      --region "$AWS_REGION" \
      --max-keys 1000 \
      --query '{Objects: (Versions[].{Key:Key,VersionId:VersionId} + DeleteMarkers[].{Key:Key,VersionId:VersionId})}' \
      --output json 2>/dev/null || echo '{"Objects":null}')

    local objects
    objects=$(echo "$batch" | jq '.Objects // []')
    [[ "$objects" == "[]" ]] && break

    aws s3api delete-objects \
      --bucket "$bucket" \
      --region "$AWS_REGION" \
      --delete "{\"Objects\": ${objects}}" \
      --output text >/dev/null
  done

  ok "Bucket $bucket emptied"
}

empty_ecr_repo() {
  local repo="$1"
  log "Emptying ECR repository: $repo"

  local deleted=0

  # Paginate through all images (tagged + untagged/orphaned), delete in batches of 100
  while true; do
    local image_ids
    image_ids=$(aws ecr list-images \
      --repository-name "$repo" \
      --region "$AWS_REGION" \
      --filter tagStatus=ANY \
      --max-items 100 \
      --query 'imageIds[*]' \
      --output json 2>/dev/null || echo "[]")

    [[ "$image_ids" == "[]" || "$image_ids" == "null" ]] && break

    aws ecr batch-delete-image \
      --repository-name "$repo" \
      --region "$AWS_REGION" \
      --image-ids "$image_ids" \
      --output text >/dev/null

    deleted=$(( deleted + $(echo "$image_ids" | jq 'length') ))
  done

  if [[ $deleted -eq 0 ]]; then
    warn "ECR repo $repo is already empty or does not exist — skipping"
  else
    ok "ECR repo $repo emptied ($deleted images deleted)"
  fi
}

# ─── 1. App ───────────────────────────────────────────────────────────────────
delete_stack "${STACK_PREFIX}-app"

# ─── 2. Backend ────────────────────────────────────────────────────────────────
delete_stack "${STACK_PREFIX}-backend"

# ─── 2. Keycloak ──────────────────────────────────────────────────────────────
delete_stack "${STACK_PREFIX}-keycloak"

# ─── 3. Frontend — empty S3 bucket before stack delete ───────────────────────
if stack_exists "${STACK_PREFIX}-frontend"; then
  BUCKET=$(cfn_output "${STACK_PREFIX}-frontend" "FrontendBucketName")
  [[ -n "$BUCKET" ]] && empty_s3_bucket "$BUCKET"
fi
delete_stack "${STACK_PREFIX}-frontend"

# ─── 4. Certificate (us-east-1) — delete after CloudFront is gone ────────────
CERT_STACK="${STACK_PREFIX}-certificate"
CERT_STATUS=$(command aws ${AWS_PROFILE:+--profile "$AWS_PROFILE"} cloudformation describe-stacks \
  --stack-name "$CERT_STACK" --region us-east-1 \
  --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "")
if [[ -n "$CERT_STATUS" && "$CERT_STATUS" != "DELETE_COMPLETE" ]]; then
  log "Deleting certificate stack: $CERT_STACK (us-east-1)"
  command aws ${AWS_PROFILE:+--profile "$AWS_PROFILE"} cloudformation delete-stack \
    --stack-name "$CERT_STACK" --region us-east-1
  command aws ${AWS_PROFILE:+--profile "$AWS_PROFILE"} cloudformation wait stack-delete-complete \
    --stack-name "$CERT_STACK" --region us-east-1 \
    && ok "Certificate stack deleted" \
    || fail "Certificate stack deletion failed"
else
  warn "Certificate stack $CERT_STACK not found — skipping"
fi

# ─── 5. Cluster + ALB ─────────────────────────────────────────────────────────
delete_stack "${STACK_PREFIX}-cluster"

# ─── 6. Cache + Spark (no dependencies on cluster) ───────────────────────────
delete_stack "${STACK_PREFIX}-cache"
delete_stack "${STACK_PREFIX}-spark"

# ─── 5. Database — disable Aurora deletion protection, then delete stack ──────
if stack_exists "${STACK_PREFIX}-database"; then
  AURORA_ID="${STACK_PREFIX}-aurora"
  if aws rds describe-db-clusters \
      --db-cluster-identifier "$AURORA_ID" \
      --region "$AWS_REGION" \
      --query 'DBClusters[0].DBClusterIdentifier' \
      --output text 2>/dev/null | grep -q "$AURORA_ID"; then
    log "Disabling deletion protection on Aurora cluster: $AURORA_ID"
    aws rds modify-db-cluster \
      --db-cluster-identifier "$AURORA_ID" \
      --no-deletion-protection \
      --apply-immediately \
      --region "$AWS_REGION" >/dev/null
    ok "Deletion protection disabled — CloudFormation will create a final snapshot"
  fi
fi
delete_stack "${STACK_PREFIX}-database"

# ─── 6. ECR — empty repositories before stack delete ─────────────────────────
for SUFFIX in backend keycloak app; do
  empty_ecr_repo "${PROJECT_NAME}-${ENVIRONMENT}/${SUFFIX}"
done
delete_stack "${STACK_PREFIX}-ecr"

# ─── 7. Network ───────────────────────────────────────────────────────────────
delete_stack "${STACK_PREFIX}-network"

# ─── 8. CI/CD (shared, not environment-specific) ─────────────────────────────
if stack_exists "${PROJECT_NAME}-cicd"; then
  echo ""
  warn "CI/CD stack '${PROJECT_NAME}-cicd' is shared across all environments."
  read -rp "Delete it as well? (yes/no): " DELETE_CICD
  if [[ "$DELETE_CICD" == "yes" ]]; then
    delete_stack "${PROJECT_NAME}-cicd"
  else
    warn "Skipped CI/CD stack"
  fi
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
ok "Teardown complete for ${STACK_PREFIX}."
echo ""
echo "Remaining manual cleanup (if needed):"
echo "  - RDS snapshots:   https://console.aws.amazon.com/rds/home?region=${AWS_REGION}#snapshots:"
echo "  - Secrets Manager: secrets enter a 7-day recovery window before permanent deletion"
echo "  - CloudWatch Logs: log groups are deleted with the cluster stack"
