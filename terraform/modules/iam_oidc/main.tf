# iam_oidc/main.tf
#
# Implements keyless authentication between GitHub Actions and AWS.
#
# How it works:
#   1. GitHub mints a short-lived OIDC JWT for each workflow run.
#   2. The workflow calls aws-actions/configure-aws-credentials with role-to-assume.
#   3. AWS STS validates the JWT against the OIDC provider registered here.
#   4. STS returns temporary credentials scoped to this IAM role.
#   5. The workflow uses those credentials — no long-lived secrets ever stored.
#
# The trust policy conditions lock the role down so only:
#   - Your specific repository
#   - The three deployment branches (develop, staging, main)
# can assume it. Any other GitHub Actions workflow in any other repo is rejected.

locals {
  # GitHub's OIDC certificate thumbprint.
  # This value is stable but check https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc_verify-thumbprint.html
  # if authentication starts failing after GitHub rotates their certificates.
  github_oidc_thumbprint = "6938fd4d98bab03faadb97b34396831e3780aea1"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [local.github_oidc_thumbprint]
  tags            = var.tags
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    # Condition 1: the token audience must be sts.amazonaws.com
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Condition 2: the token subject must match your repo and one of the
    # three deployment branches. Any other repo or branch is denied.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main",
        "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/staging",
        "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/develop",
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = var.tags
}

# Policy 1: ECR push permissions
# GetAuthorizationToken must be * because it is an account-level action —
# it cannot be scoped to a specific repository ARN.
# The actual push actions are scoped to the specific repository ARNs.
data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "ECRAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = var.ecr_repository_arns
  }
}

# Policy 2: ECS deploy permissions
# DescribeTaskDefinition and DescribeServices must be * because they
# accept task definition ARNs but the ARN is not known until after
# render-task-definition runs. The write actions (Register, Update)
# could be scoped further in a hardened environment.
data "aws_iam_policy_document" "ecs_deploy" {
  statement {
    sid    = "ECSRead"
    effect = "Allow"
    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:DescribeServices",
      "ecs:DescribeTasks",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ECSDeploy"
    effect = "Allow"
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:UpdateService",
    ]
    resources = ["*"]
  }

  # PassRole allows CI to hand the execution and task roles to ECS
  # when registering a new task definition revision.
  # Scoped to only the specific role name patterns used in this project.
  statement {
    sid     = "PassRole"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      "arn:aws:iam::*:role/*-ecs-execution-role",
      "arn:aws:iam::*:role/*-ecs-task-role",
    ]
  }
}

resource "aws_iam_policy" "ecr_push" {
  name        = "${var.role_name}-ecr-push"
  description = "Allows GitHub Actions to push images to specified ECR repositories"
  policy      = data.aws_iam_policy_document.ecr_push.json
  tags        = var.tags
}

resource "aws_iam_policy" "ecs_deploy" {
  name        = "${var.role_name}-ecs-deploy"
  description = "Allows GitHub Actions to register task definitions and update ECS services"
  policy      = data.aws_iam_policy_document.ecs_deploy.json
  tags        = var.tags
}

resource "aws_iam_role_policy_attachment" "ecr_push" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.ecr_push.arn
}

resource "aws_iam_role_policy_attachment" "ecs_deploy" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.ecs_deploy.arn
}