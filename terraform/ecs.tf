# =============================================================================
# CloudWatch Log Group for ECS
# =============================================================================
resource "aws_cloudwatch_log_group" "ecs" {
  name = "/ecs/${var.app_name}"

  # 30 days minimum for incident investigation
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
# =============================================================================
resource "aws_lb" "main" {
  name               = "${var.app_name}-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  # Enable deletion protection in production
  enable_deletion_protection = var.environment == "production"

  tags = {
    Name        = "${var.app_name}-alb"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# =============================================================================
# ALB Target Group
# =============================================================================
resource "aws_lb_target_group" "app" {
  name        = "${var.app_name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }

  tags = {
    Name        = "${var.app_name}-tg"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# =============================================================================
# HTTP Listener
# =============================================================================
# HTTP is intentionally used for the initial ALB integration.
# HTTPS + ACM certificate will be added in the TLS phase.
resource "aws_lb_listener" "app_http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# =============================================================================
# ECS Task Definition
# =============================================================================
resource "aws_ecs_task_definition" "devsecops_td" {
  family                   = "${var.app_name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "${var.app_name}-app"
      image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
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

      # ECS container health check
      # Mirrors the Docker HEALTHCHECK and uses the application's /health endpoint.
      healthCheck = {
        command     = ["CMD-SHELL", "wget -qO- http://localhost:${var.container_port}/health | grep -q '\"status\":\"healthy\"' || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 15
      }

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

      # Secrets will be added through SSM Parameter Store / Secrets Manager.
      # Never pass production secrets as plain environment variables.
      #
      # secrets = [
      #   {
      #     name      = "ADMIN_API_KEY"
      #     valueFrom = "..."
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

      # Read-only root filesystem
      readonlyRootFilesystem = true

      # Drop Linux capabilities
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
    # ECS tasks remain private and are never directly internet-facing.
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  # Automatically roll back failed deployments.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_controller {
    type = "ECS"
  }

  # Register ECS tasks with the ALB target group.
  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "${var.app_name}-app"
    container_port   = var.container_port
  }

  # Ensure the ALB listener exists before ECS registers the service.
  depends_on = [
    aws_lb_listener.app_http
  ]

  tags = {
    Name        = "${var.app_name}-service"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}