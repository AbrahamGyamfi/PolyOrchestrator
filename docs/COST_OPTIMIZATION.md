# BusinessConnect — Cost Optimization Guide

This document captures the cost levers available for the BusinessConnect infrastructure
and provides rough monthly estimates based on **eu-west-1 (Ireland)** on-demand pricing
as of mid-2025. Actual bills will vary with traffic and AWS pricing changes.

---

## 1. Compute: ECS Fargate vs EKS t3.medium

### ECS Fargate (current default)

Fargate bills per vCPU-hour and GB-hour of memory consumed by running tasks.

| Service | vCPU | Memory | Tasks (min/max) | Est. $/month (min) |
|---|---|---|---|---|
| auth-service | 0.25 | 0.5 GB | 2 / 6 | ~$9 |
| business-service | 0.5 | 1 GB | 2 / 8 | ~$18 |
| review-service | 0.25 | 0.5 GB | 1 / 4 | ~$4.50 |
| inquiry-service | 0.25 | 0.5 GB | 1 / 4 | ~$4.50 |
| gateway | 0.25 | 0.5 GB | 2 / 8 | ~$9 |
| frontend | 0.25 | 0.5 GB | 2 / 6 | ~$9 |
| postgres | 0.5 | 1 GB | 1 (fixed) | ~$9 |
| redis | 0.25 | 0.5 GB | 1 (fixed) | ~$4.50 |

**Fargate total at minimum replicas: ~$67/month**
**Fargate total at maximum replicas: ~$200/month**

> Fargate pricing (eu-west-1): ~$0.04048/vCPU-hour, ~$0.004445/GB-hour

### EKS on t3.medium (alternative)

Two t3.medium nodes (2 vCPU, 4 GB each) can run the full workload.

| Item | Cost/month |
|---|---|
| EKS control plane | $73 |
| 2 × t3.medium On-Demand | ~$62 |
| **Total** | **~$135/month** |

EKS breaks even vs. Fargate only at higher replica counts. For dev/staging, Fargate
with `ecs_min_capacity = 1` is cheaper. EKS becomes cost-effective at sustained
scale (6+ replicas across all services).

---

## 2. NAT Gateway Removal — $32/month Saved

A single NAT Gateway in eu-west-1 costs **~$32/month** ($0.044/hour) before any
data-processing charges. The current architecture places all ECS tasks in public
subnets with `assign_public_ip = true`, so services pull ECR images and reach AWS
APIs directly — no NAT Gateway is needed. Removing it saves the full $32/month.

**Action:** Confirm no workloads route through a NAT GW before applying.

---

## 3. Spot Instance Savings — ~60-70% Per Node

Enabling `eks_enable_spot = true` replaces On-Demand EKS nodes with Spot instances.

| Instance | On-Demand/month | Spot/month (typical) | Savings |
|---|---|---|---|
| t3.medium | ~$31 | ~$9-12 | ~65% |
| Per node (3-node cluster) | ~$93 | ~$28-36 | ~$57-65 |

For a 3-node EKS cluster, switching to Spot saves roughly **$55-65/month**.
Spot is suitable for stateless services (auth, business, review, inquiry, gateway,
frontend). Run postgres and redis on On-Demand or use managed services (RDS, ElastiCache)
for reliability.

---

## 4. ECS Auto-Scaling Benefits

The `autoscaling.tf` configures `aws_appautoscaling_target` with:

- **`ecs_min_capacity = 1`** — scale down to a single task per service during
  off-hours, reducing Fargate spend by up to 50% vs. a fixed desired count of 2.
- **`ecs_max_capacity = 4`** — caps runaway scaling events.
- **CPU target: 70%** — scale-out before tasks become unresponsive; scale-in after
  a 300-second stabilization window to avoid flapping.

Estimated saving from scaling to 1 replica per service overnight (8 hours/day):

| Service | Idle saving/day | Idle saving/month |
|---|---|---|
| auth-service (0.25 vCPU, 1 replica saved) | ~$0.10 | ~$3 |
| business-service (0.5 vCPU, 1 replica saved) | ~$0.19 | ~$5.70 |
| gateway (0.25 vCPU, 1 replica saved) | ~$0.10 | ~$3 |
| frontend (0.25 vCPU, 1 replica saved) | ~$0.10 | ~$3 |

**Total auto-scaling savings (dev/staging): ~$15-20/month**

---

## 5. CloudWatch Logs — 7-Day Retention

AWS CloudWatch Logs charges **$0.57/GB/month** for stored log data (eu-west-1).
All `aws_cloudwatch_log_group` resources in `ecs.tf` are set to `retention_in_days = 7`.

| Retention | Relative storage | Monthly cost (1 GB/day ingest) |
|---|---|---|
| 30 days (default) | 30 GB | ~$17 |
| 7 days | 7 GB | ~$4 |
| **Saving** | | **~$13/month** |

For production, consider 14 or 30 days and enable log export to S3 (long-term
archival at ~$0.023/GB/month) before reducing retention further.

---

## 6. ECR Lifecycle Policy — Keep 10 Images

Each ECR image layer is stored at **$0.10/GB/month**. Without a lifecycle policy,
every CI push accumulates images indefinitely. The `ecr.tf` lifecycle policy retains
only the 10 most recent tagged images per repository.

Assuming average image size of 300 MB and 50 CI pushes/month:

| Policy | Images retained | Storage | Monthly cost |
|---|---|---|---|
| None (50 pushes/month × 6 months) | 300 | ~90 GB | ~$9 |
| Keep 10 | 10 | ~3 GB | ~$0.30 |
| **Saving** | | | **~$8.70/month** |

---

## 7. Summary — Monthly Savings Table

| Optimization | Before | After | Saving/month |
|---|---|---|---|
| Remove NAT Gateway | ~$32 | $0 | **$32** |
| ECS auto-scaling (min=1 off-hours) | ~$67 (fixed ×2) | ~$50 | **~$17** |
| CloudWatch 7-day retention | ~$17 | ~$4 | **~$13** |
| ECR lifecycle (keep 10) | ~$9 | ~$0.30 | **~$8.70** |
| EKS Spot instances (if using EKS) | ~$93 | ~$30 | **~$63** |
| **Total (ECS path)** | | | **~$71/month** |
| **Total (EKS + Spot path)** | | | **~$117/month** |

> All figures are estimates. Run `aws ce get-cost-and-usage` or review Cost Explorer
> monthly to track actual spend against these projections.
