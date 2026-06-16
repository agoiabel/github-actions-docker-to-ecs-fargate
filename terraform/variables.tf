# variables.tf — all inputs that vary between runs but are not
# environment-specific config (those live in locals.tf).

variable "aws_region" {
  description = "AWS region where all resources are created"
  type        = string
}

variable "app_name" {
  description = <<-EOT
    Short application name used as a prefix on every AWS resource.
    Keep it lowercase, alphanumeric, and under 20 characters.
    Example: ecs-demo
  EOT
  type        = string
}

variable "github_org" {
  description = "GitHub organisation name or personal account username"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name without the org prefix"
  type        = string
}

variable "container_port" {
  description = "Port number the container listens on. Must match EXPOSE in Dockerfile"
  type        = number
  default     = 3000
}

variable "health_check_path" {
  description = <<-EOT
    HTTP path used by both the ALB target group health check and the
    container-level health check in the task definition.
    Must return HTTP 200 with no external dependencies.
  EOT
  type        = string
  default     = "/health"
}