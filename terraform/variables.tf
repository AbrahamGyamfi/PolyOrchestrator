variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project / application name prefix used for all resource names"
  type        = string
  default     = "businessconnect"
}

variable "environment" {
  description = "Deployment environment (dev | staging | prod)"
  type        = string
  default     = "dev"
}

# ── Network ──────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDRs for the two public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs for the two private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

# ── Auth ─────────────────────────────────────────────────────────────────────

variable "better_auth_secret" {
  description = "Secret key for better-auth (≥ 32 random chars)"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true
  default     = "postgres"
}

variable "frontend_url" {
  description = "Public URL of the frontend (used by auth redirects)"
  type        = string
  default     = "http://localhost:3000"
}

# ── ECS ───────────────────────────────────────────────────────────────────────

variable "ecs_service_desired_count" {
  description = "Default desired task count for ECS services"
  type        = number
  default     = 2
}

# ── EKS ───────────────────────────────────────────────────────────────────────

variable "eks_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.31"
}

variable "eks_node_instance_type" {
  description = "EC2 instance type for EKS managed node group"
  type        = string
  default     = "t3.medium"
}

variable "eks_node_min" {
  type    = number
  default = 2
}

variable "eks_node_max" {
  type    = number
  default = 4
}

variable "eks_node_desired" {
  type    = number
  default = 2
}

variable "ecs_min_capacity" {
  description = "Minimum number of ECS tasks per service (auto-scaling lower bound)"
  type        = number
  default     = 1
}

variable "ecs_max_capacity" {
  description = "Maximum number of ECS tasks per service (auto-scaling upper bound)"
  type        = number
  default     = 4
}

variable "ecs_cpu_target" {
  description = "Target CPU utilization percentage for ECS auto-scaling"
  type        = number
  default     = 70
}

variable "eks_enable_spot" {
  description = "Enable Spot instance node group for cost savings (~60-70% cheaper than On-Demand)"
  type        = bool
  default     = false
}
