# The bootstrap stack: what has to exist before the other two stacks and CI can work. The S3
# bucket for Terraform state, the link that lets GitHub Actions sign in to AWS (an OIDC
# provider) and the two IAM roles it signs in as. You apply this once, by hand, with admin
# credentials. CI never touches it. See docs/decisions/0003 and "Set up" in ../README.md.

terraform {
  required_version = ">= 1.11"

  # State: this stack keeps its state LOCALLY, in this folder (terraform.tfstate, gitignored).
  # It can't live in the bucket it creates until the bucket exists, and it holds no secrets
  # (no passwords, only names and ARNs). If you lose the file, nothing breaks; you re-import
  # the resources (see "If you lose the bootstrap state" in ../README.md). Keeping the roles'
  # own state out of the bucket also means the CI roles can never be given access to it.
  # There is no `backend` block on purpose.

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
