output "repository_url" {
  description = "Full ECR repository URI — used as the image base in CI and task definitions"
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ARN of the repository — used to scope the IAM push policy"
  value       = aws_ecr_repository.this.arn
}