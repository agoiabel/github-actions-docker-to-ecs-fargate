variable "name" {
  description = "Name prefix for all networking resources"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Must not overlap with other environments"
  type        = string
}

variable "availability_zones" {
  description = "List of AZs to spread subnets across. Provide at least 2 for ALB"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = <<-EOT
    CIDR blocks for public subnets — one per AZ.
    The ALB lives here. Dev ECS tasks also live here to avoid NAT Gateway cost.
  EOT
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = <<-EOT
    CIDR blocks for private subnets — one per AZ.
    Staging and prod ECS tasks live here. Outbound traffic routes via NAT Gateway.
  EOT
  type        = list(string)
}

variable "single_nat_gateway" {
  description = <<-EOT
    When true, a single NAT Gateway is created and shared across all private subnets.
    Cost-effective for dev and staging. Set to false in prod for AZ-level resilience.
  EOT
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to every networking resource"
  type        = map(string)
  default     = {}
}