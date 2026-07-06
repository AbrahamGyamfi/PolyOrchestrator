# ── Network ───────────────────────────────────────────────────────────────────

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

# ── ECR ───────────────────────────────────────────────────────────────────────

output "ecr_repository_urls" {
  description = "Map of service name → ECR repository URL"
  value       = module.ecr.repository_urls
}

# ── ECS ───────────────────────────────────────────────────────────────────────

output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}

output "alb_dns_name" {
  description = "ALB public DNS — set as VITE_API_URL for the frontend build"
  value       = module.ecs.alb_dns_name
}

output "cloud_map_namespace" {
  description = "Private DNS namespace for ECS service discovery"
  value       = module.ecs.cloud_map_namespace
}

# ── EKS ───────────────────────────────────────────────────────────────────────

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_cluster_ca" {
  value     = module.eks.cluster_ca
  sensitive = true
}

output "eks_kubeconfig_command" {
  description = "Run this command to configure kubectl for the EKS cluster"
  value       = module.eks.kubeconfig_command
}
