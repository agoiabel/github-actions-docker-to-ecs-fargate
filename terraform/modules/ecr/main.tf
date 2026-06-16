# ecr/main.tf
#
# Creates a private ECR repository with:
#   - AES256 encryption at rest
#   - Scan on push (detects known CVEs in image layers automatically)
#   - Lifecycle policy to prevent unbounded image accumulation

resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = var.image_tag_mutability

  # Encrypt images at rest using AWS-managed keys
  encryption_configuration {
    encryption_type = "AES256"
  }

  # Automatically scan every pushed image for known CVE vulnerabilities.
  # Results appear in the ECR console and can trigger SNS alerts.
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  # Two rules keep the repository from growing indefinitely:
  #   Rule 1: Delete untagged images after 1 day.
  #           Untagged images are intermediate build cache artefacts —
  #           they accumulate fast and cost money if left uncleaned.
  #   Rule 2: Keep only the last 30 tagged images per environment prefix.
  #           Older images are expired automatically.
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the last 30 images per environment prefix"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["dev-", "staging-", "prod-"]
          countType     = "imageCountMoreThan"
          countNumber   = 30
        }
        action = { type = "expire" }
      }
    ]
  })
}