# The foundation stack: the DynamoDB table, the Lambda function's role and the alarms.
# See docs/decisions/0003-split-stacks-remote-state-and-ci-deploys.md and docs/decisions/0006-move-to-lambda-and-dynamodb.md.

terraform {
  required_version = ">= 1.11"

  # State in the bucket from infra/bootstrap; pass the bucket and region with `terraform init -backend-config=../backend.hcl`.
  # use_lockfile locks the state while a run changes it.
  backend "s3" {
    key          = "foundation/terraform.tfstate"
    use_lockfile = true
    encrypt      = true
  }

  # The plugin ("provider") Terraform downloads on `terraform init`.
  # `~> 6.0` means any 6.x version, but not 7.0.
  # The exact version used is pinned in .terraform.lock.hcl.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Tells the AWS provider which region to create everything in.
# Credentials are not set here; the provider reads them from your AWS CLI profile or environment variables.
provider "aws" {
  region = var.region

  # Tags added to every resource that supports tags, so you can find them in the console and in billing reports.
  default_tags {
    tags = {
      Project   = var.name
      Stack     = "foundation"
      ManagedBy = "terraform"
    }
  }
}
