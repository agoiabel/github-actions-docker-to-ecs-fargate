output "cluster_name" {
  description = "Name of the ECS cluster — stored as GitHub environment secret ECS_CLUSTER"
  value       = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.this.arn
}