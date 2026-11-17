# The bootstrap stack: what has to exist before the other two stacks and CI can work. The S3
# bucket for Terraform state, and the two IAM roles GitHub Actions signs in as, each with an
# IAM user to sign in with. You apply this once, by hand, with admin credentials. CI never
# touches it. See docs/decisions/0003, 0004 and "Set up and first run" in ../README.md.

terraform {
  required_version = ">= 1.11"

  # State in the bucket this stack creates. The bucket doesn't exist on the very first apply,
  # so that one runs with a local backend_override.tf (gitignored) and the state is moved here
  # afterwards (see "Set up and first run" in ../README.md). Both CI roles are denied this key.
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
