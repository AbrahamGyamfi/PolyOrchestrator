# ── ALB (internet-facing) ─────────────────────────────────────────────────────

resource "aws_security_group" "alb" {
  name        = "${var.project}-sg-alb"
  description = "Allow HTTP/HTTPS from anywhere"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-sg-alb" }
}

# ── Frontend (Nginx container on port 3000) ───────────────────────────────────

resource "aws_security_group" "frontend" {
  name        = "${var.project}-sg-frontend"
  description = "Frontend: accepts traffic from ALB only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "From ALB"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-sg-frontend" }
}

# ── Gateway (port 4000) ───────────────────────────────────────────────────────

resource "aws_security_group" "gateway" {
  name        = "${var.project}-sg-gateway"
  description = "API Gateway: accepts traffic from frontend"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "From frontend"
    from_port       = 4000
    to_port         = 4000
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-sg-gateway" }
}

# ── Auth Service (port 4001) ──────────────────────────────────────────────────

resource "aws_security_group" "auth_service" {
  name        = "${var.project}-sg-auth"
  description = "Auth service: accepts from gateway"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "From gateway"
    from_port       = 4001
    to_port         = 4001
    protocol        = "tcp"
    security_groups = [aws_security_group.gateway.id]
  }

  # Business/review/inquiry services call auth for session validation
  ingress {
    description     = "From backend services"
    from_port       = 4001
    to_port         = 4001
    protocol        = "tcp"
    security_groups = [aws_security_group.backend_services.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-sg-auth" }
}

# ── Business / Review / Inquiry services (ports 4002–4004) ───────────────────

resource "aws_security_group" "backend_services" {
  name        = "${var.project}-sg-backend-services"
  description = "Backend services: business, review, inquiry"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "From gateway"
    from_port       = 4002
    to_port         = 4004
    protocol        = "tcp"
    security_groups = [aws_security_group.gateway.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-sg-backend-services" }
}

# ── Redis (port 6379) ─────────────────────────────────────────────────────────

resource "aws_security_group" "redis" {
  name        = "${var.project}-sg-redis"
  description = "Redis: accepts from auth and backend services"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "From auth service"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.auth_service.id]
  }

  ingress {
    description     = "From backend services"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.backend_services.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-sg-redis" }
}

# ── PostgreSQL (port 5432) ────────────────────────────────────────────────────

resource "aws_security_group" "postgres" {
  name        = "${var.project}-sg-postgres"
  description = "PostgreSQL: accepts from auth and backend services"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "From auth service"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.auth_service.id]
  }

  ingress {
    description     = "From backend services"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.backend_services.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-sg-postgres" }
}

# ── EKS nodes ─────────────────────────────────────────────────────────────────

resource "aws_security_group" "eks_nodes" {
  name        = "${var.project}-sg-eks-nodes"
  description = "EKS worker nodes"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Node-to-node traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description     = "From ALB"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-sg-eks-nodes" }
}
