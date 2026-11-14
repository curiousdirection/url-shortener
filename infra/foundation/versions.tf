# The foundation stack: the parts that change rarely and are expensive to get wrong. The
# network, the database, its firewall, the two IAM roles ECS uses, and the database password.
# The app stack (../app) reads what it needs from here. See docs/decisions/0003.
#
# CI never plans or applies this stack. You plan and apply it yourself, from your machine
# (see "Deploy" in ../README.md).

terraform {
  # Write-only arguments (used for the database password below) need Terraform 1.11 or newer.
  # S3 state locking with a lock file (use_lockfile) needs 1.10 or newer.
  required_version = ">= 1.11"

  # State: where Terraform records what it has created. It lives in the S3 bucket made by
  # ../bootstrap, so that CI and your machine see the same state. The bucket name and region
  # are not written here, because they differ per AWS account. Pass them when you initialise:
  #   terraform init -backend-config=../backend.hcl      (see ../backend.hcl.example)
  backend "s3" {
    # One state file per stack, in the same bucket.
    key = "foundation/terraform.tfstate"
    # Locking: Terraform writes a small ".tflock" file next to the state while it runs, so two
    # runs can't change the same state at once. (No DynamoDB table is needed any more.)
    use_lockfile = true
    # Encrypt the state at rest.
    encrypt = true
  }

  # Plugins ("providers") Terraform downloads on `terraform init`. `~> 6.0` means any 6.x
  # version, but not 7.0. The exact versions used are pinned in .terraform.lock.hcl.
  required_providers {
    # Creates the AWS resources.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # Generates the random database password and the snapshot name suffix. 3.7 is the first
    # version with ephemeral resources, which keep the password out of the state.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

# Tells the AWS provider which region to create everything in. Credentials are not set here;
# the provider reads them from your AWS CLI profile or environment variables.
provider "aws" {
  region = var.region

  # Tags added to every resource that supports tags, so you can find them in the console
  # and in billing reports.
  default_tags {
    tags = {
      Project   = var.name
      Stack     = "foundation"
      ManagedBy = "terraform"
    }
  }
}
