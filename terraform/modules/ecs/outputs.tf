output "cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "alb_dns_name" {
  description = "ALB public DNS — use as VITE_API_URL for the frontend build"
  value       = aws_lb.main.dns_name
}

output "cloud_map_namespace" {
  description = "Private DNS namespace for ECS service discovery"
  value       = aws_service_discovery_private_dns_namespace.main.name
}
