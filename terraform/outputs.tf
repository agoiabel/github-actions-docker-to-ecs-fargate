# outputs.tf
#
# Every value you need to copy into GitHub environment secrets is printed here
# after `terraform apply` completes. Nothing needs to be looked up manually.

output "alb_dns_name" {
  description = "Public URL to test your application. Use curl http://<this value>/health"
  value       = module.alb.alb_dns_name
}

output "ecr_repository_url" {
  description = "Full ECR repository URI. CI pushes images here"
  value       = module.ecr.repository_url
}

output "github_actions_role_arn" {
  description = "→ GitHub environment secret: AWS_ROLE_ARN"
  value       = module.iam_oidc.role_arn
}

output "ecs_cluster_name" {
  description = "→ GitHub environment secret: ECS_CLUSTER"
  value       = module.ecs_cluster.cluster_name
}

output "ecs_service_name" {
  description = "→ GitHub environment secret: ECS_SERVICE"
  value       = module.ecs_service.service_name
}

output "ecs_container_name" {
  description = "→ GitHub environment secret: ECS_CONTAINER_NAME"
  value       = module.ecs_service.container_name
}

output "ecs_task_definition_family" {
  description = "→ GitHub environment secret: ECS_TASK_DEFINITION"
  value       = module.ecs_service.task_definition_family
}

output "vpc_id" {
  description = "ID of the created VPC"
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.networking.private_subnet_ids
}