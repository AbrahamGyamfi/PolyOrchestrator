#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 01-build-push.sh
# Builds all service images and pushes them to Amazon ECR.
#
# Prerequisites: aws-cli v2, docker, jq
# Usage:
#   export AWS_REGION=us-east-1
#   export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
#   ./scripts/01-build-push.sh [--tag <tag>]
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
ACCOUNT="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
PROJECT="businessconnect"
TAG="${1:-latest}"
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"

# Root of the businessConnect project (one level up from scripts/)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Authenticating with ECR (${REGISTRY})"
aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY}"

# Map: local build context → ECR repository name
declare -A SERVICES=(
  ["${ROOT}/frontend"]="${PROJECT}/frontend"
  ["${ROOT}/migrate"]="${PROJECT}/migrate"
  ["${ROOT}/services/auth-service"]="${PROJECT}/auth-service"
  ["${ROOT}/services/business-service"]="${PROJECT}/business-service"
  ["${ROOT}/services/review-service"]="${PROJECT}/review-service"
  ["${ROOT}/services/inquiry-service"]="${PROJECT}/inquiry-service"
  ["${ROOT}/services/gateway"]="${PROJECT}/gateway"
)

for CONTEXT in "${!SERVICES[@]}"; do
  REPO="${SERVICES[$CONTEXT]}"
  IMAGE="${REGISTRY}/${REPO}:${TAG}"

  echo ""
  echo "==> Building ${REPO}  (context: ${CONTEXT})"
  docker build \
    --platform linux/amd64 \
    --build-arg VITE_API_URL="" \
    -t "${IMAGE}" \
    "${CONTEXT}"

  echo "==> Pushing ${IMAGE}"
  docker push "${IMAGE}"
done

echo ""
echo "✅  All images pushed to ECR under tag '${TAG}'."
echo "    Registry: ${REGISTRY}"
echo ""
echo "Next step: update Kubernetes deployment image tags or trigger ECS service update."
