output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

# ── ECR ───────────────────────────────────────────────────────────────────────

output "ecr_repository_urls" {
  description = "Map of service name → ECR repository URL"
  value       = { for k, v in aws_ecr_repository.services : k => v.repository_url }
}

# ── ECS ───────────────────────────────────────────────────────────────────────

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "alb_dns_name" {
  description = "ALB public DNS — set as VITE_API_URL for the frontend build"
  value       = aws_lb.main.dns_name
}

output "cloud_map_namespace" {
  description = "Private DNS namespace for ECS service discovery"
  value       = aws_service_discovery_private_dns_namespace.main.name
}

# ── EKS ───────────────────────────────────────────────────────────────────────

output "eks_cluster_name" {
  value = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "eks_cluster_ca" {
  value     = aws_eks_cluster.main.certificate_authority[0].data
  sensitive = true
}

output "eks_kubeconfig_command" {
  description = "Run this command to configure kubectl for the EKS cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}
