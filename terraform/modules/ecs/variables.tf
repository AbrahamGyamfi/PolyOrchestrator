variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

# ── Network ───────────────────────────────────────────────────────────────────

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

# ── Security Groups ───────────────────────────────────────────────────────────

variable "alb_sg_id" {
  type = string
}

variable "frontend_sg_id" {
  type = string
}

variable "gateway_sg_id" {
  type = string
}

variable "auth_service_sg_id" {
  type = string
}

variable "backend_services_sg_id" {
  type = string
}

variable "redis_sg_id" {
  type = string
}

variable "postgres_sg_id" {
  type = string
}

# ── IAM ───────────────────────────────────────────────────────────────────────

variable "ecs_execution_role_arn" {
  type = string
}

variable "ecs_task_role_arn" {
  type = string
}

# ── ECR ───────────────────────────────────────────────────────────────────────

variable "ecr_repository_urls" {
  type        = map(string)
  description = "Map of service name → ECR repository URL from the ecr module"
}

# ── Application ───────────────────────────────────────────────────────────────

variable "better_auth_secret" {
  type      = string
  sensitive = true
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "frontend_url" {
  type = string
}

variable "ecs_service_desired_count" {
  type    = number
  default = 2
}

variable "ecs_min_capacity" {
  type    = number
  default = 1
}

variable "ecs_max_capacity" {
  type    = number
  default = 4
}

variable "ecs_cpu_target" {
  type    = number
  default = 70
}
