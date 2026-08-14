provider "aws" {
  region  = var.aws_region
  profile = "terraform"

  default_tags {
    tags = {
      Project     = "Enterprise DevSecOps Platform"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
