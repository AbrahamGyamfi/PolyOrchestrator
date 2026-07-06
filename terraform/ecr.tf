# One ECR repository per deployable image.
# Postgres and Redis use public DockerHub images and don't need ECR repos.

locals {
  ecr_repos = [
    "frontend",
    "auth-service",
    "business-service",
    "review-service",
    "inquiry-service",
    "gateway",
    "migrate",
  ]
}

resource "aws_ecr_repository" "services" {
  for_each = toset(local.ecr_repos)

  name                 = "${var.project}/${each.key}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "${var.project}/${each.key}" }
}

# Lifecycle policy: keep only the 10 most recent images per repo
resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
