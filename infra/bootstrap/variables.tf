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

variable "github_repository" {
  description = "The GitHub repository allowed to assume the roles, as owner/name."
  type        = string
  default     = "curiousdirection/url-shortener"
}

variable "github_environment" {
  description = "The GitHub environment whose jobs may assume the deploy role (Settings > Environments)."
  type        = string
  default     = "production"
}

variable "create_github_oidc_provider" {
  description = "An AWS account can only have one GitHub OIDC provider. Set this to false if the account already has one (it is looked up instead of created)."
  type        = bool
  default     = true
}

variable "github_oidc_sub_prefix" {
  description = "The start of the `sub` claim in GitHub's tokens, before the environment or branch part. Leave empty for the classic form, `repo:<owner>/<repo>`. GitHub repositories created or renamed after 15 July 2026 use an ID-based form instead, e.g. `repo:<owner>@<owner id>/<repo>@<repo id>`. If the first workflow run is refused, copy the prefix from the `sub` in its error (see \"Set up and first run\" in infra/README.md)."
  type        = string
  default     = ""
}
