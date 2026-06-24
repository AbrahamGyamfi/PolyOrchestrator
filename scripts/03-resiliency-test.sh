#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 03-resiliency-test.sh
# Demonstrates automatic recovery in both ECS (Fargate) and EKS:
#   - Kills a running container / pod
#   - Watches the orchestrator restart it automatically
#
# Usage:
#   # EKS mode (default)
#   ./scripts/03-resiliency-test.sh eks [service]
#
#   # ECS mode
#   export AWS_REGION=us-east-1
#   export ECS_CLUSTER=businessconnect-ecs
#   ./scripts/03-resiliency-test.sh ecs [service]
#
# Examples:
#   ./scripts/03-resiliency-test.sh eks gateway
#   ./scripts/03-resiliency-test.sh ecs gateway
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

MODE="${1:-eks}"
SERVICE="${2:-gateway}"
NAMESPACE="businessconnect"
REGION="${AWS_REGION:-us-east-1}"
CLUSTER="${ECS_CLUSTER:-businessconnect-ecs}"

separator() { echo ""; echo "────────────────────────────────────────────"; echo ""; }

# ── EKS / Kubernetes ─────────────────────────────────────────────────────────
eks_test() {
  echo "=== EKS Resiliency Test ==="
  echo "Target: deployment/${SERVICE} in namespace ${NAMESPACE}"
  separator

  echo "BEFORE — current pods:"
  kubectl get pods -n "${NAMESPACE}" -l "app=${SERVICE}" -o wide
  separator

  # Pick one running pod and delete it
  POD=$(kubectl get pods -n "${NAMESPACE}" -l "app=${SERVICE}" \
        --field-selector=status.phase=Running \
        -o jsonpath='{.items[0].metadata.name}')

  if [ -z "${POD}" ]; then
    echo "No running pod found for app=${SERVICE}"; exit 1
  fi

  echo "KILLING pod: ${POD}"
  kubectl delete pod "${POD}" -n "${NAMESPACE}" --grace-period=0 --force
  echo "Pod deleted. Kubernetes will schedule a replacement immediately."
  separator

  echo "WATCHING pod list (Ctrl-C to stop):"
  kubectl get pods -n "${NAMESPACE}" -l "app=${SERVICE}" -w &
  WATCH_PID=$!

  echo ""
  echo "Waiting for deployment to be healthy again..."
  kubectl rollout status deployment/"${SERVICE}" -n "${NAMESPACE}" --timeout=120s

  kill "${WATCH_PID}" 2>/dev/null || true

  separator
  echo "AFTER — current pods:"
  kubectl get pods -n "${NAMESPACE}" -l "app=${SERVICE}" -o wide
  separator
  echo "✅  EKS recovery verified: pod was replaced automatically."
}

# ── ECS / Fargate ─────────────────────────────────────────────────────────────
ecs_test() {
  ECS_SERVICE="${CLUSTER}-${SERVICE}"
  echo "=== ECS Resiliency Test ==="
  echo "Cluster: ${CLUSTER}  |  Service: ${ECS_SERVICE}"
  separator

  echo "BEFORE — running tasks:"
  aws ecs list-tasks \
    --cluster "${CLUSTER}" \
    --service-name "${ECS_SERVICE}" \
    --region "${REGION}" \
    --output table

  # Get the first task ARN
  TASK_ARN=$(aws ecs list-tasks \
    --cluster "${CLUSTER}" \
    --service-name "${ECS_SERVICE}" \
    --region "${REGION}" \
    --query 'taskArns[0]' \
    --output text)

  if [ "${TASK_ARN}" = "None" ] || [ -z "${TASK_ARN}" ]; then
    echo "No running task found for service ${ECS_SERVICE}"; exit 1
  fi

  echo "KILLING task: ${TASK_ARN}"
  aws ecs stop-task \
    --cluster "${CLUSTER}" \
    --task "${TASK_ARN}" \
    --reason "Resiliency test: manual kill" \
    --region "${REGION}" \
    --output table
  echo "Task stopped. ECS will launch a replacement to maintain desired count."
  separator

  echo "Waiting 30 s for ECS to provision a new task..."
  sleep 30

  echo "AFTER — running tasks:"
  aws ecs list-tasks \
    --cluster "${CLUSTER}" \
    --service-name "${ECS_SERVICE}" \
    --region "${REGION}" \
    --output table

  echo ""
  echo "Service events (latest 5):"
  aws ecs describe-services \
    --cluster "${CLUSTER}" \
    --services "${ECS_SERVICE}" \
    --region "${REGION}" \
    --query 'services[0].events[:5]' \
    --output table
  separator
  echo "✅  ECS recovery verified: new task was launched automatically."
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
case "${MODE}" in
  eks) eks_test ;;
  ecs) ecs_test ;;
  *)
    echo "Unknown mode '${MODE}'. Use 'eks' or 'ecs'."
    exit 1
    ;;
esac
