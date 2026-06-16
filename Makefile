BUCKET   := agoi-ecs-demo
REGION   := us-east-1
ENV      ?= dev

TF_DIR   := terraform
TFVARS   := $(TF_DIR)/envs/$(ENV).tfvars
STATE_KEY := $(BUCKET)/$(ENV)/terraform.tfstate

# dev: no locking (fast iteration); staging + prod: native S3 locking (Terraform >= 1.10)
ifeq ($(ENV),dev)
  LOCK_FLAG := -backend-config="use_lockfile=false"
else
  LOCK_FLAG := -backend-config="use_lockfile=true"
endif

BACKEND_FLAGS := \
  -backend-config="bucket=$(BUCKET)" \
  -backend-config="key=$(STATE_KEY)" \
  -backend-config="region=$(REGION)" \
  $(LOCK_FLAG)

.PHONY: init workspace plan apply destroy fmt validate create-backend help

create-backend:
	aws s3api create-bucket \
	  --bucket $(BUCKET) \
	  --region $(REGION)
	aws s3api put-bucket-versioning \
	  --bucket $(BUCKET) \
	  --versioning-configuration Status=Enabled
	aws s3api put-public-access-block \
	  --bucket $(BUCKET) \
	  --public-access-block-configuration \
	  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
	aws s3api put-bucket-encryption \
	  --bucket $(BUCKET) \
	  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

init:
	terraform -chdir=$(TF_DIR) init $(BACKEND_FLAGS) -reconfigure

workspace: init
	terraform -chdir=$(TF_DIR) workspace new $(ENV) 2>/dev/null || \
	terraform -chdir=$(TF_DIR) workspace select $(ENV)

plan: workspace
	terraform -chdir=$(TF_DIR) plan -var-file=envs/$(ENV).tfvars

apply: workspace
	terraform -chdir=$(TF_DIR) apply -var-file=envs/$(ENV).tfvars

destroy: workspace
	terraform -chdir=$(TF_DIR) destroy -var-file=envs/$(ENV).tfvars

fmt:
	terraform -chdir=$(TF_DIR) fmt -recursive

validate: workspace
	terraform -chdir=$(TF_DIR) validate

help:
	@echo "Usage: make <target> [ENV=dev|staging|prod]"
	@echo ""
	@echo "Targets:"
	@echo "  init      Init backend for ENV (default: dev)"
	@echo "  workspace Create or select workspace for ENV"
	@echo "  plan      Plan changes for ENV"
	@echo "  apply     Apply changes for ENV"
	@echo "  destroy   Destroy resources for ENV"
	@echo "  fmt       Format all Terraform files"
	@echo "  validate        Validate Terraform configuration"
	@echo "  create-backend  Create and configure the S3 state bucket"
