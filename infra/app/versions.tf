# The app stack: the parts that change on every release. The container image repository, the
# log group and the ECS Express Mode service. Everything it depends on (network, database,
# roles) is in ../foundation. See docs/decisions/0003.
#
# This is the only stack that CI applies (.github/workflows/deploy.yml), with the
# `github-deploy-url-shortener` role from ../bootstrap.

terraform {
  required_version = ">= 1.11"

  # State: see ../foundation/versions.tf. Same bucket, its own state file.
  #   terraform init -backend-config=../backend.hcl      (see ../backend.hcl.example)
  backend "s3" {
    key          = "app/terraform.tfstate"
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
      Stack     = "app"
      ManagedBy = "terraform"
    }
  }
}
