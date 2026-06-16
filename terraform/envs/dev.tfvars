# dev.tfvars — values for the dev workspace.
# Run with: terraform apply -var-file=envs/dev.tfvars

aws_region  = "us-east-1"
app_name    = "agoi-ecs-demo"
github_org  = "agoiabel"    # ← replace with your GitHub username
github_repo = "github-actions-docker-to-ecs-fargate"        # ← replace with your repository name