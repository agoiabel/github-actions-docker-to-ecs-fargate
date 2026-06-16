# networking/outputs.tf
# These outputs are consumed directly by the alb and ecs_service modules
# in the root main.tf — no values need to be copy-pasted anywhere.

output "vpc_id" {
  description = "ID of the created VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets — passed to the ALB module"
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "IDs of the private subnets — passed to the ECS service module for staging and prod"
  value       = module.vpc.private_subnets
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC — useful for security group rules"
  value       = module.vpc.vpc_cidr_block
}