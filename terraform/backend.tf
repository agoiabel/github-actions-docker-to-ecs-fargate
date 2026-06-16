terraform {
  # The backend block is intentionally left empty.
  #
  # Why: this single file is shared by dev, staging, and prod workspaces.
  # Dev should have no state locking (fast iteration, solo developer).
  # Staging and prod need use_lockfile = true (prevent concurrent applies).
  #
  # The only clean way to vary locking behaviour per environment from a
  # single backend.tf is to inject all values at `terraform init` time
  # using -backend-config flags. See Step 3 for the exact init commands.
  #
  # Requires Terraform >= 1.10 for native S3 locking via use_lockfile.
  backend "s3" {}
}