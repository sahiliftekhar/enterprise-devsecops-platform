# =============================================================================
# CloudWatch Log Group for ECS
# =============================================================================
resource "aws_cloudwatch_log_group" "ecs" {
  name = "/ecs/${var.app_name}"

  # 30 days minimum for incident investigation (was 7 — too short for forensics)
  retention_in_days = 30

  tags = {
    Name        = "${var.app_name}-logs"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# =============================================================================
# ECS Cluster
# =============================================================================
resource "aws_ecs_cluster" "main" {
  name = "${var.app_name}-cluster"

  configuration {
    execute_command_configuration {
      logging = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = true
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.ecs.name
      }
    }
  }

  # Enable Container Insights for enhanced metrics and monitoring
  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name        = "${var.app_name}-cluster"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# =============================================================================
# Application Load Balancer
# Uncomment when your AWS account supports ALB creation.
# ECS tasks should NEVER be directly internet-facing (assign_public_ip = true
# on ECS service is a HIGH severity finding — H-6). Always use an ALB.
# =============================================================================

# resource "aws_lb" "main" {
#   name               = "${var.app_name}-alb"
#   internal           = false
#   load_balancer_type = "application"
#   security_groups    = [aws_security_group.alb.id]
#   subnets            = aws_subnet.public[*].id
#
#   # Enable deletion protection in production
#   enable_deletion_protection = var.environment == "production" ? true : false
#
#   # Enable access logs for security auditing
#   access_logs {
#     bucket  = aws_s3_bucket.alb_logs.bucket
#     prefix  = "${var.app_name}-alb"
#     enabled = true
#   }
#
#   tags = {
#     Name        = "${var.app_name}-alb"
#     Environment = var.environment
#     ManagedBy   = "terraform"
#   }
# }

# resource "aws_lb_target_group" "app" {
#   name        = "${var.app_name}-tg"
#   port        = var.container_port
#   protocol    = "HTTP"
#   vpc_id      = aws_vpc.main.id
#   target_type = "ip"
#
#   health_check {
#     enabled             = true
#     healthy_threshold   = 2
#     interval            = 30
#     matcher             = "200"
#     path                = "/health"
#     port                = "traffic-port"
#     protocol            = "HTTP"
#     timeout             = 5
#     unhealthy_threshold = 3
#   }
#
#   tags = {
#     Name        = "${var.app_name}-tg"
#     Environment = var.environment
#     ManagedBy   = "terraform"
#   }
# }

# resource "aws_lb_listener" "app_http" {
#   load_balancer_arn = aws_lb.main.arn
#   port              = "80"
#   protocol          = "HTTP"
#
#   # In production, redirect HTTP → HTTPS instead of forwarding
#   default_action {
#     type = "redirect"
#     redirect {
#       port        = "443"
#       protocol    = "HTTPS"
#       status_code = "HTTP_301"
#     }
#   }
# }

# resource "aws_lb_listener" "app_https" {
#   load_balancer_arn = aws_lb.main.arn
#   port              = "443"
#   protocol          = "HTTPS"
#   ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"  # TLS 1.3 preferred
#   certificate_arn   = var.acm_certificate_arn
#
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.app.arn
#   }
# }

# =============================================================================
# ECS Task Definition
# =============================================================================
resource "aws_ecs_task_definition" "devsecops_td" {
  family                   = "${var.app_name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.ecs_task_execution_role_arn

  container_definitions = jsonencode([
    {
      name      = "${var.app_name}-app"
      image     = "${var.ecr_repo_url}:${var.image_tag}"
      cpu       = tonumber(var.cpu)
      memory    = tonumber(var.memory)
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]

      # Health check mirrors the Docker HEALTHCHECK — uses /health endpoint
      healthCheck = {
        command     = ["CMD-SHELL", "wget -qO- http://localhost:${var.container_port}/health | grep -q '\"status\":\"healthy\"' || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 15
      }

      # Inject the API key for /toggle-health via Secrets Manager or SSM.
      # Never pass secrets as plain environment variables in production;
      # use the 'secrets' field with valueFrom pointing to SSM/SecretsManager.
      environment = [
        {
          name  = "NODE_ENV"
          value = var.environment
        },
        {
          name  = "PORT"
          value = tostring(var.container_port)
        }
      ]

      # secrets = [
      #   {
      #     name      = "ADMIN_API_KEY"
      #     valueFrom = "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/${var.app_name}/admin-api-key"
      #   }
      # ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = var.app_name
        }
      }

      # Read-only root filesystem reduces the blast radius of a container escape
      readonlyRootFilesystem = true

      # Drop all Linux capabilities and only add the minimum required
      linuxParameters = {
        capabilities = {
          drop = ["ALL"]
          add  = []
        }
        # Prevent privilege escalation inside the container
        initProcessEnabled = false
      }
    }
  ])

  tags = {
    Name        = "${var.app_name}-task"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# =============================================================================
# ECS Service
# =============================================================================
resource "aws_ecs_service" "devsecops_service" {
  name            = "${var.app_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.devsecops_td.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.app_subnet_ids
    security_groups = [var.app_security_group_id]

    # assign_public_ip = false means tasks get no direct internet-facing IP.
    # Traffic should enter via the ALB (public subnets) only.
    # If you are not yet using an ALB, temporarily set this to true and restrict
    # ingress to port 3000 in the security group — but enable the ALB ASAP.
    assign_public_ip = false
  }

  # Deployment circuit breaker — automatically rolls back failed deployments
  # instead of leaving the service in a broken state.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_controller {
    type = "ECS"
  }

  # Uncomment the load_balancer block once the ALB is provisioned.
  # load_balancer {
  #   target_group_arn = aws_lb_target_group.app.arn
  #   container_name   = "${var.app_name}-app"
  #   container_port   = var.container_port
  # }

  depends_on = [aws_ecs_task_definition.devsecops_td]

  tags = {
    Name        = "${var.app_name}-service"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
