# ════════════════════════════════════════════════════════════════════════════
#  ECS Cluster
# ════════════════════════════════════════════════════════════════════════════

resource "aws_ecs_cluster" "main" {
  name = "${var.project}-ecs"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${var.project}-ecs" }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

# ════════════════════════════════════════════════════════════════════════════
#  CloudWatch Log Groups
# ════════════════════════════════════════════════════════════════════════════

locals {
  log_services = ["postgres", "redis", "auth-service", "business-service",
                  "review-service", "inquiry-service", "gateway", "frontend", "migrate"]
}

resource "aws_cloudwatch_log_group" "services" {
  for_each          = toset(local.log_services)
  name              = "/ecs/${var.project}/${each.key}"
  retention_in_days = 7
}

# ════════════════════════════════════════════════════════════════════════════
#  Cloud Map (Service Discovery)
# ════════════════════════════════════════════════════════════════════════════

resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "${var.project}.local"
  description = "Private DNS namespace for BusinessConnect microservices"
  vpc         = aws_vpc.main.id
}

locals {
  # Services that need to be discoverable by other services
  discovery_services = ["postgres", "redis", "auth-service",
                        "business-service", "review-service",
                        "inquiry-service", "gateway"]
}

resource "aws_service_discovery_service" "services" {
  for_each = toset(local.discovery_services)

  name = each.key

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.main.id
    routing_policy = "MULTIVALUE"

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

# ════════════════════════════════════════════════════════════════════════════
#  Application Load Balancer (public, routes to frontend)
# ════════════════════════════════════════════════════════════════════════════

resource "aws_lb" "main" {
  name               = "${var.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = { Name = "${var.project}-alb" }
}

resource "aws_lb_target_group" "frontend" {
  name        = "${var.project}-tg-frontend"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"   # required for Fargate (awsvpc network mode)

  health_check {
    path                = "/"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200-399"
  }

  tags = { Name = "${var.project}-tg-frontend" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

# ════════════════════════════════════════════════════════════════════════════
#  ECS Task Definitions
# ════════════════════════════════════════════════════════════════════════════

locals {
  ns = "${var.project}.local"   # Cloud Map namespace shorthand
}

# ── PostgreSQL ────────────────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "postgres" {
  family                   = "${var.project}-postgres"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "postgres"
    image     = "postgres:16-alpine"
    essential = true
    portMappings = [{ containerPort = 5432, protocol = "tcp" }]
    environment = [
      { name = "POSTGRES_DB",       value = "church_platform" },
      { name = "POSTGRES_USER",     value = "postgres" },
      { name = "POSTGRES_PASSWORD", value = var.db_password },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options   = {
        "awslogs-group"         = "/ecs/${var.project}/postgres"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# ── Redis ─────────────────────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "redis" {
  family                   = "${var.project}-redis"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "redis"
    image     = "redis:7-alpine"
    essential = true
    portMappings = [{ containerPort = 6379, protocol = "tcp" }]
    logConfiguration = {
      logDriver = "awslogs"
      options   = {
        "awslogs-group"         = "/ecs/${var.project}/redis"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# ── Auth Service ──────────────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "auth_service" {
  family                   = "${var.project}-auth-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "auth-service"
    image     = "${aws_ecr_repository.services["auth-service"].repository_url}:latest"
    essential = true
    portMappings = [{ containerPort = 4001, protocol = "tcp" }]
    environment = [
      { name = "DATABASE_URL",       value = "postgres://postgres:${var.db_password}@postgres.${local.ns}:5432/church_platform" },
      { name = "REDIS_URL",          value = "redis://redis.${local.ns}:6379" },
      { name = "BETTER_AUTH_SECRET", value = var.better_auth_secret },
      { name = "GATEWAY_URL",        value = "http://gateway.${local.ns}:4000" },
      { name = "FRONTEND_URL",       value = var.frontend_url },
      { name = "PORT",               value = "4001" },
    ]
    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://localhost:4001/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 30
    }
    logConfiguration = {
      logDriver = "awslogs"
      options   = {
        "awslogs-group"         = "/ecs/${var.project}/auth-service"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# ── Business Service ──────────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "business_service" {
  family                   = "${var.project}-business-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "business-service"
    image     = "${aws_ecr_repository.services["business-service"].repository_url}:latest"
    essential = true
    portMappings = [{ containerPort = 4002, protocol = "tcp" }]
    environment = [
      { name = "DATABASE_URL",      value = "postgres://postgres:${var.db_password}@postgres.${local.ns}:5432/church_platform" },
      { name = "AUTH_SERVICE_URL",  value = "http://auth-service.${local.ns}:4001" },
      { name = "UPLOADS_DIR",       value = "/uploads" },
      { name = "PORT",              value = "4002" },
    ]
    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://localhost:4002/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 30
    }
    logConfiguration = {
      logDriver = "awslogs"
      options   = {
        "awslogs-group"         = "/ecs/${var.project}/business-service"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# ── Review Service ────────────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "review_service" {
  family                   = "${var.project}-review-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "review-service"
    image     = "${aws_ecr_repository.services["review-service"].repository_url}:latest"
    essential = true
    portMappings = [{ containerPort = 4003, protocol = "tcp" }]
    environment = [
      { name = "DATABASE_URL",     value = "postgres://postgres:${var.db_password}@postgres.${local.ns}:5432/church_platform" },
      { name = "AUTH_SERVICE_URL", value = "http://auth-service.${local.ns}:4001" },
      { name = "PORT",             value = "4003" },
    ]
    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://localhost:4003/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 30
    }
    logConfiguration = {
      logDriver = "awslogs"
      options   = {
        "awslogs-group"         = "/ecs/${var.project}/review-service"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# ── Inquiry Service ───────────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "inquiry_service" {
  family                   = "${var.project}-inquiry-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "inquiry-service"
    image     = "${aws_ecr_repository.services["inquiry-service"].repository_url}:latest"
    essential = true
    portMappings = [{ containerPort = 4004, protocol = "tcp" }]
    environment = [
      { name = "DATABASE_URL",     value = "postgres://postgres:${var.db_password}@postgres.${local.ns}:5432/church_platform" },
      { name = "AUTH_SERVICE_URL", value = "http://auth-service.${local.ns}:4001" },
      { name = "PORT",             value = "4004" },
    ]
    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://localhost:4004/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 30
    }
    logConfiguration = {
      logDriver = "awslogs"
      options   = {
        "awslogs-group"         = "/ecs/${var.project}/inquiry-service"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# ── Gateway ───────────────────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "gateway" {
  family                   = "${var.project}-gateway"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "gateway"
    image     = "${aws_ecr_repository.services["gateway"].repository_url}:latest"
    essential = true
    portMappings = [{ containerPort = 4000, protocol = "tcp" }]
    environment = [
      { name = "AUTH_SERVICE_URL",     value = "http://auth-service.${local.ns}:4001" },
      { name = "BUSINESS_SERVICE_URL", value = "http://business-service.${local.ns}:4002" },
      { name = "REVIEW_SERVICE_URL",   value = "http://review-service.${local.ns}:4003" },
      { name = "INQUIRY_SERVICE_URL",  value = "http://inquiry-service.${local.ns}:4004" },
      { name = "FRONTEND_URL",         value = var.frontend_url },
      { name = "PORT",                 value = "4000" },
    ]
    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://localhost:4000/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 15
    }
    logConfiguration = {
      logDriver = "awslogs"
      options   = {
        "awslogs-group"         = "/ecs/${var.project}/gateway"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# ── Frontend ──────────────────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "frontend" {
  family                   = "${var.project}-frontend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "frontend"
    image     = "${aws_ecr_repository.services["frontend"].repository_url}:latest"
    essential = true
    portMappings = [{ containerPort = 3000, protocol = "tcp" }]
    environment = [
      # Nginx proxies /api/* to the gateway via this env var (envsubst at container start)
      { name = "GATEWAY_URL", value = "http://gateway.${local.ns}:4000" },
    ]
    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://localhost:3000 || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 15
    }
    logConfiguration = {
      logDriver = "awslogs"
      options   = {
        "awslogs-group"         = "/ecs/${var.project}/frontend"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# ════════════════════════════════════════════════════════════════════════════
#  ECS Services
# ════════════════════════════════════════════════════════════════════════════

# ── Migrate (one-shot task definition — run manually with aws ecs run-task) ───

resource "aws_ecs_task_definition" "migrate" {
  family                   = "${var.project}-migrate"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "migrate"
    image     = "${aws_ecr_repository.services["migrate"].repository_url}:latest"
    essential = true
    environment = [
      { name = "DATABASE_URL", value = "postgres://postgres:${var.db_password}@postgres.${local.ns}:5432/church_platform" },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options   = {
        "awslogs-group"         = "/ecs/${var.project}/migrate"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# ── PostgreSQL service ────────────────────────────────────────────────────────

resource "aws_ecs_service" "postgres" {
  name            = "${var.project}-postgres"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.postgres.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.postgres.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services["postgres"].arn
  }

  lifecycle { ignore_changes = [desired_count] }
}

# ── Redis service ─────────────────────────────────────────────────────────────

resource "aws_ecs_service" "redis" {
  name            = "${var.project}-redis"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.redis.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.redis.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services["redis"].arn
  }

  lifecycle { ignore_changes = [desired_count] }
}

# ── Auth Service ──────────────────────────────────────────────────────────────

resource "aws_ecs_service" "auth_service" {
  name            = "${var.project}-auth-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.auth_service.arn
  desired_count   = var.ecs_service_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.auth_service.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services["auth-service"].arn
  }

  depends_on = [aws_ecs_service.postgres, aws_ecs_service.redis]
  lifecycle  { ignore_changes = [desired_count] }
}

# ── Business Service ──────────────────────────────────────────────────────────

resource "aws_ecs_service" "business_service" {
  name            = "${var.project}-business-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.business_service.arn
  desired_count   = var.ecs_service_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.backend_services.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services["business-service"].arn
  }

  depends_on = [aws_ecs_service.auth_service]
  lifecycle  { ignore_changes = [desired_count] }
}

# ── Review Service ────────────────────────────────────────────────────────────

resource "aws_ecs_service" "review_service" {
  name            = "${var.project}-review-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.review_service.arn
  desired_count   = var.ecs_service_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.backend_services.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services["review-service"].arn
  }

  depends_on = [aws_ecs_service.auth_service]
  lifecycle  { ignore_changes = [desired_count] }
}

# ── Inquiry Service ───────────────────────────────────────────────────────────

resource "aws_ecs_service" "inquiry_service" {
  name            = "${var.project}-inquiry-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.inquiry_service.arn
  desired_count   = var.ecs_service_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.backend_services.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services["inquiry-service"].arn
  }

  depends_on = [aws_ecs_service.auth_service]
  lifecycle  { ignore_changes = [desired_count] }
}

# ── Gateway ───────────────────────────────────────────────────────────────────

resource "aws_ecs_service" "gateway" {
  name            = "${var.project}-gateway"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.gateway.arn
  desired_count   = var.ecs_service_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.gateway.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services["gateway"].arn
  }

  depends_on = [
    aws_ecs_service.auth_service,
    aws_ecs_service.business_service,
    aws_ecs_service.review_service,
    aws_ecs_service.inquiry_service,
  ]
  lifecycle { ignore_changes = [desired_count] }
}

# ── Frontend ──────────────────────────────────────────────────────────────────

resource "aws_ecs_service" "frontend" {
  name            = "${var.project}-frontend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = var.ecs_service_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.frontend.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = 3000
  }

  depends_on = [aws_ecs_service.gateway, aws_lb_listener.http]
  lifecycle  { ignore_changes = [desired_count] }
}
