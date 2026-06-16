variable "name" {
  description = "Name prefix for ALB resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID from the networking module output"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs from the networking module. ALB requires at least 2 AZs"
  type        = list(string)
}

variable "container_port" {
  description = "Port the ECS tasks listen on — ALB forwards traffic here"
  type        = number
  default     = 3000
}

variable "health_check_path" {
  description = "Path the ALB polls to determine if a target is healthy"
  type        = string
  default     = "/health"
}

variable "deregistration_delay" {
  description = <<-EOT
    Seconds the ALB waits for in-flight requests to complete before
    removing a deregistered target. Lower values mean faster deploys.
    Higher values protect long-running requests during rolling updates.
  EOT
  type    = number
  default = 30
}

variable "tags" {
  description = "Tags applied to ALB resources"
  type        = map(string)
  default     = {}
}