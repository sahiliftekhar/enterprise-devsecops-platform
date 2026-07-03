variable "app_name" {
  description = "Application name"
  type        = string
  default     = "devsecops-app"
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, production)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "environment must be one of: dev, staging, production."
  }
}

variable "image_tag" {
  description = "Docker image tag to deploy (e.g. the CI build number). Never use 'latest' in production."
  type        = string
  default     = "latest"
}

variable "aws_account_id" {
  description = "AWS account ID (used to build resource ARNs)"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "container_port" {
  description = "Container port"
  type        = number
  default     = 3000
}

variable "desired_count" {
  description = "Desired number of tasks"
  type        = number
  default     = 1
}

variable "cpu" {
  description = "Fargate CPU units"
  type        = string
  default     = "256"
}

variable "memory" {
  description = "Fargate memory in MB"
  type        = string
  default     = "512"
}

variable "ecs_task_execution_role_arn" {
  description = "ARN of the IAM role for ECS task execution"
  type        = string
}

variable "ecr_repo_url" {
  description = "ECR image repo url (without tag)."
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

# Required by the error messages
variable "app_subnet_ids" {
  description = "A list of subnet IDs for the ECS service."
  type        = list(string)
}

# Required by the error messages
variable "app_security_group_id" {
  description = "The security group ID for the ECS tasks."
  type        = string
}
