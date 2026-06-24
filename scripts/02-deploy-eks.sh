#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 02-deploy-eks.sh
# Replaces ECR image placeholders in the K8s manifests and applies them
# to the EKS cluster.
#
# Prerequisites: aws-cli v2, kubectl, envsubst (part of gettext)
# Usage:
#   export AWS_REGION=us-east-1
#   export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
#   ./scripts/02-deploy-eks.sh [--tag <tag>]
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
ACCOUNT="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
CLUSTER="businessconnect-eks"
# Accept either a bare tag (v1.0.0) or the --tag flag (--tag v1.0.0)
if [[ "${1:-}" == "--tag" ]]; then
  TAG="${2:-latest}"
else
  TAG="${1:-latest}"
fi
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
K8S="${ROOT}/k8s"

echo "==> Configuring kubectl for EKS cluster '${CLUSTER}'"
aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER}"

echo "==> Applying namespace, configmap, and secrets"
kubectl apply -f "${K8S}/00-namespace.yaml"
kubectl apply -f "${K8S}/01-configmap.yaml"
kubectl apply -f "${K8S}/02-secrets.yaml"

echo "==> Applying infrastructure (postgres, redis)"
kubectl apply -f "${K8S}/postgres/"
kubectl apply -f "${K8S}/redis/"

echo "==> Waiting for postgres to be ready"
kubectl rollout status deployment/postgres -n businessconnect --timeout=120s

echo "==> Applying microservices"
# Substitute the ECR image placeholders before applying
for SVC in auth-service business-service review-service inquiry-service gateway frontend; do
  DIR="${K8S}/${SVC}"
  echo "  -> ${SVC}"
  for MANIFEST in "${DIR}"/*.yaml; do
    sed \
      -e "s|<ACCOUNT_ID>|${ACCOUNT}|g" \
      -e "s|<REGION>|${REGION}|g" \
      -e "s|:latest|:${TAG}|g" \
      "${MANIFEST}" \
    | kubectl apply -f -
  done
done

echo "==> Applying Ingress"
kubectl apply -f "${K8S}/ingress/"

echo "==> Waiting for all deployments to roll out"
for DEP in auth-service business-service review-service inquiry-service gateway frontend; do
  kubectl rollout status deployment/"${DEP}" -n businessconnect --timeout=180s
done

echo ""
echo "✅  EKS deployment complete!"
echo ""
echo "==> Fetching Ingress address (may take 60–90 s for ALB to provision):"
kubectl get ingress businessconnect-ingress -n businessconnect \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null \
  && echo "" || echo "   (not yet available — run: kubectl get ingress -n businessconnect)"
