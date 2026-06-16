# networking/main.tf
#
# Uses the official community module for VPC creation.
# Source: https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws
#
# What this creates:
#   - One VPC with DNS hostnames enabled (required for ECR pull via PrivateLink)
#   - Public subnets: one per AZ — ALB nodes and dev tasks live here
#   - Private subnets: one per AZ — staging and prod tasks live here
#   - Internet Gateway: allows inbound traffic to the public subnets
#   - NAT Gateway(s): allows outbound traffic from private subnets (ECR pull, etc.)
#   - Route tables: public subnets route to IGW, private subnets route to NAT

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = var.name
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  public_subnets  = var.public_subnet_cidrs
  private_subnets = var.private_subnet_cidrs

  # NAT Gateway enables tasks in private subnets to pull images from ECR
  # and reach the internet for outbound calls without being publicly reachable.
  enable_nat_gateway = true

  # single_nat_gateway = true: one NAT Gateway shared across all AZs.
  # Cheaper but if that AZ fails, private subnet tasks in other AZs lose
  # outbound connectivity. Acceptable for dev/staging, not for prod.
  single_nat_gateway = var.single_nat_gateway

  # Required for ECS tasks to resolve ECR endpoint hostnames and for
  # CloudWatch log delivery to work correctly inside the VPC.
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tag public subnets so the ALB controller can discover them
  public_subnet_tags = {
    "type" = "public"
  }

  # Tag private subnets so ECS can discover them for task placement
  private_subnet_tags = {
    "type" = "private"
  }

  tags = var.tags
}