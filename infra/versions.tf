# State: Terraform records what it has created in a file (terraform.tfstate). There is no
# `backend` block here, so that file is kept locally in this folder. It contains the DB
# password in plain text, so it is gitignored. See README.md ("Local state").

terraform {
  # Refuse to run with an older Terraform than this.
  required_version = ">= 1.9"

  # Plugins ("providers") Terraform downloads on `terraform init`. `~> 6.0` means any 6.x
  # version, but not 7.0. The exact versions used are pinned in .terraform.lock.hcl.
  required_providers {
    # Creates the AWS resources.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # Generates the random database password.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
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
      ManagedBy = "terraform"
    }
  }
}
