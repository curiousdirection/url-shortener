# The app stack: the parts that change on every release. The Lambda function, its URL and the
# log group. Everything it depends on (the table and the function's role) is in ../foundation.
# See docs/decisions/0003 and 0006.
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

# The web ACL must be in us-east-1 (waf.tf).
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = var.name
      Stack     = "app"
      ManagedBy = "terraform"
    }
  }
}
