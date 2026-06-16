# main.tf — root module
#
# Wires all child modules together. The order of module blocks does not matter —
# Terraform builds a dependency graph from the references between outputs and inputs.
#
# Module dependency chain:
#   networking → alb (needs vpc_id, public_subnet_ids)
#   networking → ecs_service (needs vpc_id, subnet_ids)
#   alb → ecs_service (needs security_group_id, target_group_arn)
#   ecr → iam_oidc (needs repository_arn)
#   ecr → ecs_service (needs repository_url)
#   ecs_cluster → ecs_service (needs cluster_name)

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # default_tags applies these tags to every resource created by this provider.
  # Individual resources and modules can add more tags via their own tags input.
  default_tags {
    tags = {
      App         = var.app_name
      Environment = local.env
      ManagedBy   = "terraform"
      Workspace   = terraform.workspace
    }
  }
}

# ── Networking ────────────────────────────────────────────────────────────────
# Creates the VPC, subnets, IGW, NAT Gateway, and route tables.
# All other modules consume outputs from this module.

module "networking" {
  source = "./modules/networking"

  name                 = "${var.app_name}-${local.env}"
  vpc_cidr             = local.current.vpc_cidr
  availability_zones   = local.availability_zones
  public_subnet_cidrs  = local.current.public_subnet_cidrs
  private_subnet_cidrs = local.current.private_subnet_cidrs
  single_nat_gateway   = local.current.single_nat_gateway

  tags = { Component = "networking" }
}

# ── ECR ───────────────────────────────────────────────────────────────────────
# Private image registry. One repository per environment.

module "ecr" {
  source = "./modules/ecr"

  repository_name      = "${var.app_name}-${local.env}"
  image_tag_mutability = local.current.image_tag_mutability

  tags = { Component = "ecr" }
}

# ── IAM OIDC ─────────────────────────────────────────────────────────────────
# Keyless GitHub Actions → AWS authentication.
# GitHub mints a short-lived JWT; AWS validates it and returns temporary credentials.

module "iam_oidc" {
  source = "./modules/iam_oidc"

  github_org          = var.github_org
  github_repo         = var.github_repo
  environment_name    = local.env
  role_name           = "${var.app_name}-github-actions-${local.env}"
  ecr_repository_arns = [module.ecr.repository_arn]

  tags = { Component = "iam" }
}

# ── ALB ───────────────────────────────────────────────────────────────────────
# Internet-facing load balancer in the public subnets.
# Forwards HTTP/80 to ECS tasks on the container port.

module "alb" {
  source = "./modules/alb"

  name                 = "${var.app_name}-${local.env}"
  vpc_id               = module.networking.vpc_id
  public_subnet_ids    = module.networking.public_subnet_ids
  container_port       = var.container_port
  health_check_path    = var.health_check_path
  deregistration_delay = local.current.deregistration_delay

  tags = { Component = "alb" }
}

# ── ECS Cluster ───────────────────────────────────────────────────────────────

module "ecs_cluster" {
  source = "./modules/ecs_cluster"

  cluster_name = "${var.app_name}-${local.env}"
  tags         = { Component = "ecs-cluster" }
}

# ── ECS Service ───────────────────────────────────────────────────────────────
# Task definition (revision 1), ECS service, security group, IAM roles, log group.
#
# Subnet selection:
#   dev  → public subnets  (assign_public_ip = true, no NAT Gateway cost)
#   staging/prod → private subnets (assign_public_ip = false, routes via NAT)

module "ecs_service" {
  source = "./modules/ecs_service"

  name               = "${var.app_name}-${local.env}"
  cluster_name       = module.ecs_cluster.cluster_name
  ecr_repository_url = module.ecr.repository_url
  environment        = local.env

  container_port    = var.container_port
  health_check_path = var.health_check_path

  cpu           = local.current.ecs_cpu
  memory        = local.current.ecs_memory
  desired_count = local.current.ecs_desired_count

  assign_public_ip = local.current.assign_public_ip
  subnet_ids = (
    local.current.assign_public_ip
    ? module.networking.public_subnet_ids
    : module.networking.private_subnet_ids
  )

  vpc_id                = module.networking.vpc_id
  alb_security_group_id = module.alb.security_group_id
  target_group_arn      = module.alb.target_group_arn

  deployment_minimum_healthy_percent = local.current.deployment_minimum_healthy_percent
  deployment_maximum_percent         = local.current.deployment_maximum_percent
  log_retention_days                 = local.current.log_retention_days

  tags = { Component = "ecs-service" }
}