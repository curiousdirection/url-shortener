variable "name" {
  description = "Prefix for resource names and tags. Must match the other stacks."
  type        = string
  default     = "url-shortener"
}

variable "region" {
  description = "AWS region. Must match the other stacks."
  type        = string
  default     = "eu-north-1"
}

variable "github_repo" {
  description = "The GitHub repository whose Deploy workflow runs on the CodeBuild runner, as owner/name."
  type        = string
  default     = "curiousdirection/url-shortener"
}

variable "deployer_github_id" {
  description = "The numeric GitHub account ID of the person whose Deploy runs may start the runner (`gh api users/<login> --jq .id`). No default: set it in terraform.tfvars."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.deployer_github_id))
    error_message = "Use the numeric ID, not the login."
  }
}
