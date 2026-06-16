# GitHub Actions → Docker → ECS Fargate

A production-ready reference for deploying a containerised Node.js application to AWS ECS Fargate using GitHub Actions and Terraform.

Three environments (dev / staging / prod) are managed from a single Terraform codebase. Every push to a deployment branch builds a Docker image, pushes it to ECR, and rolls it out to the matching ECS service — all without storing a single long-lived AWS credential.

---

## Table of Contents

1. [Architecture overview](#architecture-overview)
2. [Repository layout](#repository-layout)
3. [The Dockerfile](#the-dockerfile)
4. [Terraform](#terraform)
   - [Module structure](#module-structure)
   - [Workspace strategy](#workspace-strategy)
   - [Environment differences](#environment-differences)
   - [Backend and state locking](#backend-and-state-locking)
   - [OIDC trust: keyless AWS auth](#oidc-trust-keyless-aws-auth)
5. [Makefile](#makefile)
6. [GitHub Actions workflow](#github-actions-workflow)
   - [Trigger rules](#trigger-rules)
   - [Job 1 — resolve-env](#job-1--resolve-env)
   - [Job 2 — build-and-push](#job-2--build-and-push)
   - [Job 3 — deploy](#job-3--deploy)
   - [Image tagging strategy](#image-tagging-strategy)
   - [Required secrets per GitHub environment](#required-secrets-per-github-environment)
7. [First-time setup](#first-time-setup)
8. [Day-to-day workflow](#day-to-day-workflow)

---

## Architecture overview

```
GitHub push
    │
    ▼
┌─────────────────────────────────────────────┐
│           GitHub Actions workflow            │
│                                             │
│  resolve-env → build-and-push → deploy      │
│                    │                │        │
│          Push image to ECR    aws ecs        │
│                               update-service │
└─────────────────────────────────────────────┘
         │ OIDC (no keys)     │
         ▼                    ▼
    ┌─────────┐        ┌─────────────────────────────────┐
    │   ECR   │        │          ECS Fargate             │
    │ (image  │──pull──│  ┌──────────┐  ┌──────────┐     │
    │registry)│        │  │  Task A  │  │  Task B  │     │
    └─────────┘        │  └──────────┘  └──────────┘     │
                       │        ▲              ▲          │
                       │        └──────────────┘          │
                       │              │                   │
                       │         ┌────────┐               │
                       │         │  ALB   │               │
                       └─────────┴────────┴───────────────┘
                                      │
                                 Internet (port 80)
```

Terraform provisions the entire AWS side: VPC, subnets, NAT gateways, ALB, ECR repository, ECS cluster + service, IAM roles, and the OIDC provider that allows GitHub Actions to authenticate to AWS without any stored access keys.

---

## Repository layout

```
.
├── Makefile                # Shorthand for all Terraform commands (see §Makefile)
├── app/
│   ├── Dockerfile          # Multi-stage Node.js image
│   ├── server.js           # HTTP server with /health endpoint
│   ├── package.json
│   └── .dockerignore
├── terraform/
│   ├── main.tf             # Root module — wires all child modules
│   ├── variables.tf        # Input variables
│   ├── locals.tf           # Per-environment config map (the single source of truth)
│   ├── outputs.tf          # Values to copy into GitHub environment secrets
│   ├── backend.tf          # S3 backend (values injected at init time)
│   ├── envs/
│   │   ├── dev.tfvars
│   │   ├── staging.tfvars
│   │   └── prod.tfvars
│   └── modules/
│       ├── networking/     # VPC, subnets, IGW, NAT, route tables
│       ├── ecr/            # ECR private repository
│       ├── iam_oidc/       # GitHub Actions ↔ AWS OIDC trust
│       ├── alb/            # Internet-facing load balancer
│       ├── ecs_cluster/    # ECS cluster
│       └── ecs_service/    # Task definition, service, IAM roles, log group
├── .github/
│   └── workflows/
│       └── deploy.yml
└── .gitignore
```

---

## The Dockerfile

`app/Dockerfile` uses a two-stage build.

```
Stage 1 — deps (node:20-alpine)
  COPY package.json
  RUN npm install --omit=dev
        │
        │  only node_modules/
        ▼
Stage 2 — runtime (node:20-alpine)
  COPY --from=deps /app/node_modules ./node_modules
  COPY . .                    ← app source only
  USER appuser                ← non-root
  EXPOSE 3000
  CMD ["node", "server.js"]
```

**Why two stages?**  
The `deps` stage installs packages using npm, which is not present in the final image. This eliminates npm, its cache, and any build-time tooling from the shipped image — reducing attack surface and image size.

**Non-root user**  
The runtime stage creates a dedicated `appuser`/`appgroup` and switches to it before the `CMD`. If an attacker exploits the application they land as an unprivileged user, not root.

**GIT_COMMIT build arg**  
CI passes `--build-arg GIT_COMMIT=${{ github.sha }}` at build time. The running container exposes it in API responses and at `/health` so you can always confirm exactly which commit is deployed.

```bash
# Build locally
docker build --build-arg GIT_COMMIT=$(git rev-parse HEAD) -t ecs-demo ./app

# Run locally
docker run -p 3000:3000 ecs-demo
curl http://localhost:3000/health
```

---

## Terraform

### Module structure

The root module in `terraform/main.tf` wires six child modules together. Terraform resolves the dependency order automatically from the references between outputs and inputs.

```
networking ──► alb
           └──► ecs_service

ecr ──► iam_oidc
    └──► ecs_service

ecs_cluster ──► ecs_service
```

| Module | What it creates |
|---|---|
| `networking` | VPC, public/private subnets across 2 AZs, internet gateway, NAT gateway(s), route tables |
| `ecr` | Private ECR repository per environment |
| `iam_oidc` | OIDC identity provider + IAM role + ECR push + ECS deploy policies |
| `alb` | Internet-facing ALB in public subnets, target group, HTTP listener |
| `ecs_cluster` | ECS cluster (Fargate capacity provider) |
| `ecs_service` | CloudWatch log group, execution role, task role, task definition (rev 1), security group, ECS service |

### Workspace strategy

All three environments are managed from a single Terraform root using [workspaces](https://developer.hashicorp.com/terraform/language/state/workspaces).

```bash
terraform workspace select dev      # activates local.env = "dev"
terraform workspace select staging
terraform workspace select prod
```

`terraform.workspace` is read in `locals.tf` as `local.env`. Every module receives its configuration from `local.current`, which is looked up from the `local.config` map. **No other file contains environment-specific conditionals.**

### Environment differences

All per-environment settings live in `terraform/locals.tf`:

| Setting | dev | staging | prod |
|---|---|---|---|
| VPC CIDR | `10.0.0.0/16` | `10.1.0.0/16` | `10.2.0.0/16` |
| ECS CPU / memory | 256 / 512 MB | 512 / 1024 MB | 1024 / 2048 MB |
| Desired task count | 1 | 1 | 2 |
| Task subnet | Public (no NAT cost) | Private | Private |
| Single NAT gateway | Yes | Yes | No (one per AZ) |
| ECR tag mutability | MUTABLE | IMMUTABLE | IMMUTABLE |
| Deploy min healthy % | 0% (fast redeploy) | 50% | 50% |
| ALB deregistration delay | 10 s | 30 s | 60 s |
| Log retention | 7 days | 14 days | 90 days |

**Dev uses public subnets for tasks** — this avoids NAT Gateway charges for ECR image pulls, which matters for a dev environment that deploys frequently.

**Prod runs two NAT gateways** — one per AZ, so if one AZ fails the remaining tasks can still pull images and reach the internet.

### Backend and state locking

`terraform/backend.tf` contains an empty `backend "s3" {}` block. All values — bucket, key, region, and locking behaviour — are injected at `terraform init` time with `-backend-config` flags.

This allows dev to skip state locking (fast iteration, solo developer) while staging and prod use `use_lockfile = true` to prevent concurrent applies. Requires Terraform >= 1.10.

```bash
# Dev (no locking)
terraform init \
  -backend-config="bucket=my-tf-state-bucket" \
  -backend-config="key=ecs-demo/dev/terraform.tfstate" \
  -backend-config="region=us-east-1"

# Staging / prod (with locking — requires Terraform >= 1.10)
terraform init \
  -backend-config="bucket=my-tf-state-bucket" \
  -backend-config="key=ecs-demo/prod/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="use_lockfile=true"
```

### OIDC trust: keyless AWS auth

The `iam_oidc` module registers GitHub's OIDC provider with AWS and creates an IAM role that GitHub Actions can assume — no AWS access keys are stored anywhere.

**How it works:**

```
GitHub Actions runner
        │
        │  1. Mint short-lived OIDC JWT
        │     (audience: sts.amazonaws.com,
        │      subject: repo:org/repo:ref:refs/heads/main)
        ▼
aws-actions/configure-aws-credentials
        │
        │  2. Call sts:AssumeRoleWithWebIdentity
        ▼
AWS STS
        │
        │  3. Validate JWT against registered OIDC provider
        │  4. Check trust policy conditions:
        │       - aud == sts.amazonaws.com  ✓
        │       - sub matches org/repo + branch  ✓
        ▼
Temporary credentials (1 hour)
        │
        ▼
GitHub Actions runner uses credentials for
  - ECR: push image
  - ECS: register task definition + update service
```

The trust policy is scoped to three branches only (`main`, `staging`, `develop`). Any other repo or branch that tries to assume this role is rejected by the `sub` condition.

---

## Makefile

A `Makefile` at the project root wraps the common Terraform commands. `ENV` defaults to `dev`; pass `ENV=staging` or `ENV=prod` to target another environment.

| Target | What it does |
|---|---|
| `make init [ENV=…]` | Initialises the S3 backend for the chosen environment |
| `make workspace [ENV=…]` | Creates or selects the Terraform workspace for `ENV` |
| `make plan [ENV=…]` | Plans changes (calls `init` → `workspace` first) |
| `make apply [ENV=…]` | Applies changes (calls `init` → `workspace` first) |
| `make destroy [ENV=…]` | Destroys resources (calls `init` → `workspace` first) |
| `make validate [ENV=…]` | Validates the configuration |
| `make fmt` | Formats all `.tf` files recursively |

`plan`, `apply`, `destroy`, and `validate` all call `init → workspace` automatically — you never need to run them as separate steps.

```bash
make apply              # dev (default)
make apply ENV=staging
make apply ENV=prod
```

---

## GitHub Actions workflow

`.github/workflows/deploy.yml` — three jobs run in sequence on every push to a deployment branch.

### Trigger rules

```yaml
on:
  push:
    branches: [develop, staging, main]
    paths:
      - 'app/**'
      - '.github/workflows/deploy.yml'
  workflow_dispatch:
```

The `paths` filter means infrastructure-only changes (Terraform edits) do not trigger a container build. `workflow_dispatch` allows manual runs from the GitHub UI.

### Job 1 — resolve-env

Maps the triggering branch to a GitHub environment name and exposes it as a job output.

```
develop → dev
staging → staging
main    → prod
```

This runs first in its own job so that `build-and-push` and `deploy` always receive the identical resolved value — there is no risk of the two jobs computing different results independently.

### Job 2 — build-and-push

Depends on `resolve-env`. Builds and pushes the Docker image to ECR.

**Step by step:**

```
checkout
    │
    ▼
get short SHA (first 7 chars of github.sha)
    │
    ▼
set up Docker Buildx
(enables multi-platform builds + registry-side cache)
    │
    ▼
configure-aws-credentials  ← OIDC, no keys
    │
    ▼
amazon-ecr-login           ← gets ECR password, calls docker login
    │
    ▼
docker/metadata-action     ← computes the three tags (see below)
    │
    ▼
docker/build-push-action
  context: ./app
  push: true
  platforms: linux/amd64,linux/arm64
  build-args: GIT_COMMIT=${{ github.sha }}
  cache-from/cache-to: ECR :buildcache tag
    │
    ▼
output image URI           ← passed to deploy job
```

**Multi-platform build** (`linux/amd64,linux/arm64`) means the image runs on both x86 EC2 and Graviton (ARM) instances without any changes.

**Registry-side layer cache** (`mode=max`) stores all layers including intermediate stages in ECR under a `:buildcache` tag. Unchanged layers are not rebuilt on the next push — significantly faster CI for iterative changes.

### Job 3 — deploy

Depends on both `resolve-env` and `build-and-push`.

```
configure-aws-credentials  ← OIDC again (credentials are not shared between jobs)
    │
    ▼
aws ecs describe-task-definition  ← download live task definition JSON
    │
    ▼
amazon-ecs-render-task-definition
  swap only the image field; leave everything else untouched
    │
    ▼
amazon-ecs-deploy-task-definition
  register new task definition revision
  update ECS service to use it
  wait-for-service-stability: true
  wait-for-minutes: 10
    │
    ▼
write job summary to GitHub UI
```

**Why download the task definition from ECS rather than committing it to the repo?**  
If the task definition JSON were stored in git, a `terraform apply` or a manual AWS Console change that updates environment variables, secrets, or log config would be silently overwritten the next time CI runs. Fetching it live means CI only ever changes the image URI — nothing else.

**What happens if the new tasks fail to start?**  
The ECS deployment circuit breaker is enabled with `rollback = true` in Terraform. If new tasks cannot reach a steady state, ECS automatically reverts the service to the previous task definition revision. The workflow step also blocks for up to 10 minutes waiting for stability, so a failed deployment surfaces as a failed workflow run.

### Image tagging strategy

Three tags are produced per build:

| Tag | Example | Purpose |
|---|---|---|
| `<env>-<short-sha>` | `prod-a3f5c8d` | **Primary.** Used by ECS. Encodes both environment and commit. |
| `<short-sha>` | `a3f5c8d` | Bare SHA for quick manual lookups. |
| `latest` | `latest` | Mutable convenience tag. Never used as the ECS image reference. |

Using `prod-a3f5c8d` as the ECS image reference means you can look at a running task definition and immediately know both which environment it belongs to and which commit it is running.

### Required secrets per GitHub environment

After `terraform apply` completes, the outputs print everything you need. Copy each value into the matching GitHub environment secret (`Settings → Environments → <env> → Secrets`).

| Secret | Terraform output | Description |
|---|---|---|
| `AWS_ROLE_ARN` | `github_actions_role_arn` | IAM role to assume via OIDC |
| `AWS_REGION` | *(from your tfvars)* | e.g. `us-east-1` |
| `ECR_REPOSITORY_URL` | `ecr_repository_url` | Full ECR URI (without tag) |
| `ECS_CLUSTER` | `ecs_cluster_name` | ECS cluster name |
| `ECS_SERVICE` | `ecs_service_name` | ECS service name |
| `ECS_CONTAINER_NAME` | `ecs_container_name` | Container name inside the task definition |
| `ECS_TASK_DEFINITION` | `ecs_task_definition_family` | Task definition family name |

---

## First-time setup

**Prerequisites:** Terraform >= 1.10, AWS CLI, a GitHub repository, an S3 bucket for Terraform state.

**1. Edit the tfvars files**

```hcl
# terraform/envs/dev.tfvars
aws_region  = "us-east-1"
app_name    = "my-app"
github_org  = "your-github-username"
github_repo = "your-repo-name"
```

Repeat for `staging.tfvars` and `prod.tfvars`.

**2. Initialise the backend for each environment**

`make init` configures the S3 backend and sets the correct locking behaviour — no lock for dev, `use_lockfile=true` for staging and prod (requires Terraform >= 1.10).

```bash
make init ENV=dev
make init ENV=staging
make init ENV=prod
```

**3. Deploy infrastructure for each environment**

`make apply` calls `init` and `workspace` automatically, but running init explicitly first gives you a clean confirmation that the backend is wired up before you apply anything.

```bash
make plan  ENV=dev      # preview first
make apply ENV=dev

make plan  ENV=staging
make apply ENV=staging

make plan  ENV=prod
make apply ENV=prod
```

**4. Copy Terraform outputs into GitHub environment secrets**

```bash
terraform -chdir=terraform workspace select dev && terraform -chdir=terraform output
```

Copy each output value into `Settings → Environments → dev → Secrets` in your GitHub repository. Repeat for staging and prod.

**5. Push to trigger the first deployment**

```bash
git push origin develop   # → deploys to dev
git push origin staging   # → deploys to staging
git push origin main      # → deploys to prod
```

---

## Day-to-day workflow

```
make a code change in app/
    │
    ▼
push to develop
    │
    ▼
CI: resolve-env → build-and-push → deploy
    (≈ 3–5 minutes end-to-end)
    │
    ▼
verify at http://<alb_dns_name>/health
  {"status":"ok"}

curl http://<alb_dns_name>/
  {"message":"Hello from ECS Fargate!","environment":"dev","commit":"a3f5c8d..."}
                                                                        ▲
                                                            matches git log --oneline
```

Once verified in dev, promote by merging to `staging`, then to `main`.

**Checking a running task's commit:**

```bash
curl http://<alb_dns_name>/ | jq .commit
```

**Rolling back manually:**

```bash
# List recent task definition revisions
aws ecs list-task-definitions --family-prefix my-app-prod --sort DESC

# Force the service to use a previous revision
aws ecs update-service \
  --cluster my-app-prod \
  --service my-app-prod \
  --task-definition my-app-prod:42
```
