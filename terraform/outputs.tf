output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "ecs_security_group_id" {
  description = "ECS tasks security group ID"
  value       = aws_security_group.ecs_tasks.id
}

# COMMENTED OUT - ALB outputs
# output "alb_dns_name" {
#   description = "ALB DNS name"
#   value       = aws_lb.main.dns_name
# }
# output "target_group_arn" {
#   description = "ALB Target group ARN"
#   value       = aws_lb_target_group.app.arn
# }
