# locals.tf — the single brain of the workspace strategy.
#
# All differences between dev, staging, and prod are expressed here.
# No other file contains environment conditionals.
# Every module reads from local.current to get the value it needs.

locals {
  # terraform.workspace is set by `terraform workspace select <name>`.
  # It will be "dev", "staging", or "prod" in normal use.
  env = terraform.workspace

  # Per-environment configuration map.
  # Adding a new environment means adding a new key here — nothing else changes.
  config = {
    dev = {
      # ── Networking ──────────────────────────────────────────────────────────
      # Each environment gets its own non-overlapping CIDR block.
      # This allows VPC peering between environments if ever needed.
      vpc_cidr            = "10.0.0.0/16"
      public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
      private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]

      # Single NAT Gateway — saves cost in dev.
      # Prod uses one per AZ for high availability.
      single_nat_gateway = true

      # ── Compute ─────────────────────────────────────────────────────────────
      ecs_cpu    = 256   # 0.25 vCPU
      ecs_memory = 512   # MB

      # One task is enough for development
      ecs_desired_count = 1

      # Allow 0 % minimum during updates — full stop/start is fine in dev
      # and makes deploys faster (no need to keep old tasks alive)
      deployment_minimum_healthy_percent = 0
      deployment_maximum_percent         = 100

      # Dev tasks use public subnets and get a public IP.
      # This avoids the NAT Gateway cost for ECR image pulls in dev.
      assign_public_ip = true

      # ── ECR ─────────────────────────────────────────────────────────────────
      # MUTABLE lets you re-push the same tag during fast iteration.
      # Staging and prod use IMMUTABLE — a tag can never be overwritten.
      image_tag_mutability = "MUTABLE"

      # ── ALB ─────────────────────────────────────────────────────────────────
      # Drain connections fast in dev — nobody cares about graceful shutdown
      deregistration_delay = 10

      # ── Logging ─────────────────────────────────────────────────────────────
      log_retention_days = 7
    }

    staging = {
      vpc_cidr             = "10.1.0.0/16"
      public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
      private_subnet_cidrs = ["10.1.11.0/24", "10.1.12.0/24"]

      single_nat_gateway = true   # still cost-conscious in staging

      ecs_cpu    = 512
      ecs_memory = 1024

      ecs_desired_count = 1

      deployment_minimum_healthy_percent = 50
      deployment_maximum_percent         = 200

      # Tasks in private subnets — traffic flows ALB → task only
      assign_public_ip = false

      image_tag_mutability = "IMMUTABLE"

      deregistration_delay = 30

      log_retention_days = 14
    }

    prod = {
      vpc_cidr             = "10.2.0.0/16"
      public_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24"]
      private_subnet_cidrs = ["10.2.11.0/24", "10.2.12.0/24"]

      # One NAT Gateway per AZ — if one AZ fails, the other AZ's
      # tasks can still pull images and reach the internet
      single_nat_gateway = false

      ecs_cpu    = 1024
      ecs_memory = 2048

      # Always 2 tasks — survive a single AZ failure
      ecs_desired_count = 2

      deployment_minimum_healthy_percent = 50
      deployment_maximum_percent         = 200

      assign_public_ip = false

      image_tag_mutability = "IMMUTABLE"

      # Drain slowly — give in-flight requests time to complete
      deregistration_delay = 60

      log_retention_days = 90
    }
  }

  # Resolve the active environment's config block.
  # Fallback to dev if the workspace is still "default".
  current = lookup(local.config, local.env, local.config["dev"])

  # Availability zones — used by the networking module.
  # Hardcoded to two AZs which is sufficient for all environments here.
  availability_zones = ["${var.aws_region}a", "${var.aws_region}b"]
}