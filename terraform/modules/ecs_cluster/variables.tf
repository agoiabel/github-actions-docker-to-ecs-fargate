variable "cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
}

variable "tags" {
  description = "Tags applied to the cluster"
  type        = map(string)
  default     = {}
}