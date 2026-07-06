output "alb_id" {
  value = aws_security_group.alb.id
}

output "frontend_id" {
  value = aws_security_group.frontend.id
}

output "gateway_id" {
  value = aws_security_group.gateway.id
}

output "auth_service_id" {
  value = aws_security_group.auth_service.id
}

output "backend_services_id" {
  value = aws_security_group.backend_services.id
}

output "redis_id" {
  value = aws_security_group.redis.id
}

output "postgres_id" {
  value = aws_security_group.postgres.id
}

output "eks_nodes_id" {
  value = aws_security_group.eks_nodes.id
}
