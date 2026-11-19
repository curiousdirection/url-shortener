# The app stack: the parts that change on every release.
# The Lambda function, its URL and the log group.
# Everything it depends on is in infra/foundation: the table and the function's role.
# See docs/decisions/0003-split-stacks-remote-state-and-ci-deploys.md and docs/decisions/0006-move-to-lambda-and-dynamodb.md.
#
# This is the only stack that CI applies (.github/workflows/deploy.yml).
# It uses the `github-deploy-url-shortener` role from infra/bootstrap.

terraform {
  required_version = ">= 1.11"

  # State: see infra/foundation/versions.tf.
  # Same bucket, its own state file.
  # See infra/backend.hcl.example.
  #   terraform init -backend-config=../backend.hcl
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
