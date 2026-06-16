# ecs_cluster/main.tf
#
# Creates an ECS cluster with:
#   - Container Insights enabled (CloudWatch metrics for CPU, memory, network per task)
#   - FARGATE and FARGATE_SPOT capacity providers available
#   - Default strategy of 1 base task on FARGATE (guaranteed) with FARGATE_SPOT for scale

resource "aws_ecs_cluster" "this" {
  name = var.cluster_name

  # Container Insights publishes per-task CloudWatch metrics.
  # Useful for debugging health check failures and performance issues.
  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = var.tags
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.this.name

  # FARGATE: dedicated capacity, always available, higher cost
  # FARGATE_SPOT: spare capacity, up to 70% cheaper, can be interrupted
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  # base = 1: always keep at least 1 task on regular FARGATE
  # weight = 1: additional tasks beyond base also go to FARGATE by default
  # Override at the service level to use FARGATE_SPOT for non-critical workloads
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}