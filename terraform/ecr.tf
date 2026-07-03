resource "aws_ecr_repository" "app" {
  name = var.app_name

  # IMMUTABLE tags prevent overwriting an existing image tag, closing a common
  # supply-chain attack vector where an attacker pushes a malicious image under
  # an already-deployed tag (e.g. "latest"). Every build must use a unique tag
  # (e.g. the CI build number) and "latest" should never be deployed directly.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    # Scan every image on push with ECR Basic Scanning (backed by Clair/Trivy).
    # For enhanced scanning (Inspector v2), enable it at the registry level.
    scan_on_push = true
  }

  encryption_configuration {
    # KMS encryption (preferred over AES256 for audit-trail and key rotation).
    # Change to encryption_type = "AES256" if a KMS key is not available.
    encryption_type = "KMS"
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
          tagStatus = "untagged"
          countType = "sinceImagePushed"
          countUnit = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last 10 tagged images (build-number tags)"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["build-"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
