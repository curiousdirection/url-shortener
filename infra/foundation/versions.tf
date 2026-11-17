# The foundation stack: network, database, ECS roles, password. CI never plans or applies it;
# you do, from your machine. See docs/decisions/0003.

terraform {
  # Write-only arguments (the database password) need 1.11.
  required_version = ">= 1.11"

  # State in the bucket from ../bootstrap; pass the bucket and region with
  # `terraform init -backend-config=../backend.hcl`. use_lockfile locks the state while a run
  # changes it.
  backend "s3" {
    key          = "foundation/terraform.tfstate"
    use_lockfile = true
    encrypt      = true
  }

  # Plugins ("providers") Terraform downloads on `terraform init`. `~> 6.0` means any 6.x
  # version, but not 7.0. The exact versions used are pinned in .terraform.lock.hcl.
  required_providers {
    # Creates the AWS resources.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # Generates the random database password (ephemeral needs 3.7).
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
