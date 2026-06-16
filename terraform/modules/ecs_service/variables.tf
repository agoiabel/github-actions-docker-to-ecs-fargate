variable "name" {
  description = "Name used for the ECS service, task definition family, and IAM roles"
  type        = string
}

variable "cluster_name" {
  description = "Name of the ECS cluster to run the service in"
  type        = string
}

variable "ecr_repository_url" {
  description = "Full ECR repository URI without a tag — CI appends the tag at deploy time"
  type        = string
}

variable "environment" {
  description = "Environment name — injected as APP_ENV into the running container"
  type        = string
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 3000
}

variable "health_check_path" {
  description = "Path used by the container-level health check command"
  type        = string
  default     = "/health"
}

variable "cpu" {
  description = "CPU units for the task. 256 = 0.25 vCPU"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Memory for the task in MB"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of task instances to keep running"
  type        = number
  default     = 1
}

variable "assign_public_ip" {
  description = <<-EOT
    true: task gets a public IP and can reach ECR directly (dev only, avoids NAT cost).
    false: task is private, outbound traffic routes through the NAT Gateway.
  EOT
  type    = bool
  default = false
}

variable "subnet_ids" {
  description = "Subnets to place tasks in. Public for dev, private for staging and prod"
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC ID — used to scope the task security group"
  type        = string
}

variable "alb_security_group_id" {
  description = "Security group ID of the ALB — tasks allow inbound only from this"
  type        = string
}

variable "target_group_arn" {
  description = "ARN of the ALB target group to register tasks with"
  type        = string
}

variable "deployment_minimum_healthy_percent" {
  description = <<-EOT
    Minimum percentage of desired tasks that must remain healthy during a deployment.
    0 in dev allows full stop/start. 50 in staging/prod keeps half the tasks alive.
  EOT
  type    = number
  default = 50
}

variable "deployment_maximum_percent" {
  description = "Maximum percentage of desired tasks that can run during a deployment"
  type        = number
  default     = 200
}

variable "log_retention_days" {
  description = "Number of days to retain logs in CloudWatch"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to all ECS service resources"
  type        = map(string)
  default     = {}
}