output "role_arn" {
  description = "ARN of the IAM role — stored as GitHub environment secret AWS_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}