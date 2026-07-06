variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "eks_version" {
  type    = string
  default = "1.31"
}

variable "eks_node_instance_type" {
  type    = string
  default = "t3.medium"
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

# ── From IAM module ───────────────────────────────────────────────────────────

variable "eks_cluster_role_arn" {
  type = string
}

variable "eks_nodes_role_arn" {
  type = string
}

# ── From VPC module ───────────────────────────────────────────────────────────

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

# ── From security-groups module ───────────────────────────────────────────────

variable "eks_nodes_sg_id" {
  type = string
}
