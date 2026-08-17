resource "aws_ecr_repository" "app" {
  name = var.app_name

  # Safety guard:
  # Never allow Terraform to destroy the ECR repository automatically.
  # This protects existing container images from accidental deletion.
  lifecycle {
    prevent_destroy = true
  }

  # Immutable tags prevent an existing image tag from being overwritten.
  # CI/CD should therefore use unique build tags such as build-123.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    # Scan images automatically when they are pushed to ECR.
    scan_on_push = true
  }

  encryption_configuration {
    # Keep the encryption type aligned with the existing repository.
    # Changing AES256 -> KMS forces ECR repository replacement.
    # Existing repository: AES256.
    encryption_type = "AES256"
  }

  tags = {
    Name        = "${var.app_name}-ecr"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"

        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }

        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep last 10 tagged build images"

        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["build-"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }

        action = {
          type = "expire"
        }
      }
    ]
  })
}