module "vpc" {
  source = "./modules/vpc"

  project              = var.project
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

module "security_groups" {
  source = "./modules/security-groups"

  project     = var.project
  environment = var.environment
  vpc_id      = module.vpc.vpc_id
}

module "iam" {
  source = "./modules/iam"

  project     = var.project
  environment = var.environment
}

module "ecr" {
  source = "./modules/ecr"

  project     = var.project
  environment = var.environment
}

module "ecs" {
  source = "./modules/ecs"

  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region

  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids

  alb_sg_id              = module.security_groups.alb_id
  frontend_sg_id         = module.security_groups.frontend_id
  gateway_sg_id          = module.security_groups.gateway_id
  auth_service_sg_id     = module.security_groups.auth_service_id
  backend_services_sg_id = module.security_groups.backend_services_id
  redis_sg_id            = module.security_groups.redis_id
  postgres_sg_id         = module.security_groups.postgres_id

  ecs_execution_role_arn = module.iam.ecs_execution_role_arn
  ecs_task_role_arn      = module.iam.ecs_task_role_arn

  ecr_repository_urls = module.ecr.repository_urls

  better_auth_secret        = var.better_auth_secret
  db_password               = var.db_password
  frontend_url              = var.frontend_url
  ecs_service_desired_count = var.ecs_service_desired_count
  ecs_min_capacity          = var.ecs_min_capacity
  ecs_max_capacity          = var.ecs_max_capacity
  ecs_cpu_target            = var.ecs_cpu_target
}

module "eks" {
  source = "./modules/eks"

  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region

  eks_version            = var.eks_version
  eks_node_instance_type = var.eks_node_instance_type
  eks_node_min           = var.eks_node_min
  eks_node_max           = var.eks_node_max
  eks_node_desired       = var.eks_node_desired

  eks_cluster_role_arn = module.iam.eks_cluster_role_arn
  eks_nodes_role_arn   = module.iam.eks_nodes_role_arn

  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
  eks_nodes_sg_id    = module.security_groups.eks_nodes_id
}
