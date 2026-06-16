variable "github_org" {
  description = "GitHub organisation or username — used to scope the OIDC trust condition"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name without the org prefix"
  type        = string
}

variable "role_name" {
  description = "Name of the IAM role GitHub Actions will assume"
  type        = string
}

variable "ecr_repository_arns" {
  description = "ARNs of ECR repositories the role is permitted to push to"
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to IAM resources"
  type        = map(string)
  default     = {}
}