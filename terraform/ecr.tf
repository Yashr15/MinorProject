# Amazon ECR — one repository per microservice
#
# ECR (Elastic Container Registry) stores your Docker images.
# Each microservice gets its own repo. Workers pull images from
# ECR when deploying pods.

resource "aws_ecr_repository" "microservices" {
  for_each = toset(var.microservices)

  name                 = "${var.project_name}/${each.key}"
  image_tag_mutability = "MUTABLE" # Allows overwriting tags (useful for :latest)
  force_delete         = true       # Allows deleting repo even with images (for dev cleanup)

  image_scanning_configuration {
    scan_on_push = true # Automatically scan images for vulnerabilities
  }

  tags = {
    Name        = each.key
    Service     = each.key
  }
}

# Lifecycle policy — auto-delete old untagged images to save storage costs
resource "aws_ecr_lifecycle_policy" "cleanup" {
  for_each = toset(var.microservices)

  repository = aws_ecr_repository.microservices[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only last 5 untagged images"
        selection = {
          tagStatus   = "untagged"
          countType   = "imageCountMoreThan"
          countNumber = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
