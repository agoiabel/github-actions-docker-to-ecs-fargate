# ecs_service/main.tf
#
# Creates:
#   - CloudWatch log group for container stdout/stderr
#   - ECS execution role (ECS pulls images and writes logs using this)
#   - ECS task role (the running container uses this to call AWS services)
#   - Task definition revision 1 (CI owns all subsequent revisions)
#   - Task security group (inbound from ALB only)
#   - ECS service with rolling update, circuit breaker, and lifecycle ignore

data "aws_region" "current" {}

# ── CloudWatch Logs ───────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "this" {
  name = "/ecs/${var.name}"

  # Logs older than this are automatically deleted.
  # Controlled per environment via local.current.log_retention_days.
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# ── IAM: Execution Role ───────────────────────────────────────────────────────
# ECS uses this role — not the running container — to:
#   - Pull the container image from ECR
#   - Write container stdout/stderr to CloudWatch Logs
#   - Retrieve secrets from Secrets Manager (if configured)
#
# The AWS-managed policy AmazonECSTaskExecutionRolePolicy covers all of these.

resource "aws_iam_role" "execution" {
  name        = "${var.name}-ecs-execution-role"
  description = "Allows ECS to pull images and write logs on behalf of tasks"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ── IAM: Task Role ────────────────────────────────────────────────────────────
# The running container uses this role to call AWS APIs from inside the task.
# Example: if your app reads from S3, you add an S3 read policy here.
# Left without any attached policies — add what your application needs.

resource "aws_iam_role" "task" {
  name        = "${var.name}-ecs-task-role"
  description = "Role assumed by the running container to call AWS services"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

# ── Task Definition ───────────────────────────────────────────────────────────
# This is revision 1 — the baseline that Terraform creates.
# CI takes ownership from revision 2 onwards via render-task-definition.
# The image is set to :latest here; CI will replace it on first deploy.

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  network_mode             = "awsvpc"       # required for Fargate
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = var.name
    image     = "${var.ecr_repository_url}:latest"
    essential = true

    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]

    environment = [
      # PORT tells the app which port to bind to
      { name = "PORT", value = tostring(var.container_port) },
      # APP_ENV is returned in API responses so you can confirm which environment is responding
      { name = "APP_ENV", value = var.environment },
    ]

    # Container-level health check — runs inside the task itself.
    # This is separate from the ALB health check.
    # Both must pass for a deployment to complete.
    #
    # startPeriod: ECS ignores failures during this window.
    # Set it to at least your app's worst-case cold start time.
    # If startPeriod is too short, tasks get killed before the app boots.
    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}${var.health_check_path} || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.this.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = var.tags
}

# ── Security Group ────────────────────────────────────────────────────────────
# Tasks accept inbound traffic only from the ALB — never from the internet.
# Outbound is open so tasks can reach ECR (image pull) and CloudWatch (logs).

resource "aws_security_group" "tasks" {
  name        = "${var.name}-tasks-sg"
  description = "Allow inbound from ALB only — deny all other inbound"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Container port from ALB only"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  egress {
    description = "All outbound - required for ECR image pull and CloudWatch logs"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

# ── ECS Service ───────────────────────────────────────────────────────────────

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = var.cluster_name
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = var.name
    container_port   = var.container_port
  }

  deployment_controller {
    type = "ECS"   # rolling update strategy
  }

  # The circuit breaker monitors the deployment and triggers a rollback
  # if the new tasks cannot reach a steady state. Without this, a broken
  # deployment retries indefinitely, leaving your service in a degraded state.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent

  # Critical: Terraform creates the task definition at revision 1 and
  # the service initially points at it. From this point forward, CI
  # calls render-task-definition and deploy-task-definition to increment
  # the revision on every deploy.
  #
  # Without this ignore_changes block, running `terraform apply` after any
  # CI deploy would revert the service back to revision 1 — undoing the deployment.
  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = var.tags
}