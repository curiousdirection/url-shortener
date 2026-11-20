# The bootstrap stack: what has to exist before the other two stacks and CI can work.
# It holds the Terraform state bucket and the deploy runner with its role.
# You apply this once, by hand, with admin credentials.
# CI never touches it.

terraform {
  required_version = ">= 1.11"

  # State in the bucket this stack creates.
  # The bucket doesn't exist on the very first apply, so that one runs with a local backend_override.tf (gitignored) and the state is moved here afterwards (see "Set up and first run" in infra/README.md).
  backend "s3" {
    key          = "bootstrap/terraform.tfstate"
    use_lockfile = true
    encrypt      = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.name
      Stack     = "bootstrap"
      ManagedBy = "terraform"
    }
  }
}
