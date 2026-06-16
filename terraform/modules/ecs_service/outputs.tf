output "service_name" {
  description = "ECS service name — stored as GitHub environment secret ECS_SERVICE"
  value       = aws_ecs_service.this.name
}

output "task_definition_family" {
  description = "Task definition family name — stored as GitHub environment secret ECS_TASK_DEFINITION"
  value       = aws_ecs_task_definition.this.family
}

output "container_name" {
  description = "Container name inside the task definition — stored as GitHub environment secret ECS_CONTAINER_NAME"
  value       = var.name
}