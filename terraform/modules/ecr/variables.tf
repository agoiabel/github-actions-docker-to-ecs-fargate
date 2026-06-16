variable "repository_name" {
  description = "Name of the ECR repository"
  type        = string
}

variable "image_tag_mutability" {
  description = <<-EOT
    MUTABLE: the same tag can be pushed multiple times (useful in dev for fast iteration).
    IMMUTABLE: once a tag is pushed it cannot be overwritten (enforced in staging and prod).
  EOT
  type    = string
  default = "IMMUTABLE"
}

variable "tags" {
  description = "Tags applied to the ECR repository"
  type        = map(string)
  default     = {}
}