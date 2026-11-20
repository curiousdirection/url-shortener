# Inputs you can change.
# The defaults are the practice values.
# To override one, put it in terraform.tfvars (gitignored) or pass `-var name=value`.
# The table settings are in infra/foundation/variables.tf.
# `state_bucket` has no default: you must set it (see below).

variable "name" {
  description = "Prefix for resource names and tags. Must match the foundation stack."
  type        = string
  default     = "url-shortener"
}

variable "region" {
  description = "AWS region. Must match the foundation stack."
  type        = string
  default     = "eu-north-1"
}

variable "state_bucket" {
  description = "The S3 bucket that holds the Terraform state (`terraform -chdir=infra/bootstrap output state_bucket`). Used to read the foundation stack's state. Set it to the same bucket as in backend.hcl: in infra/app/terraform.tfvars on your machine; CI sets it from the TF_STATE_BUCKET variable."
  type        = string

  validation {
    condition     = length(var.state_bucket) > 0
    error_message = "state_bucket must not be empty."
  }
}

variable "app_version" {
  description = "The release being deployed (scripts/app-version.sh: the first 7 characters of the commit). Shown in the function's description. No default, so pass -var app_version=... on every apply and destroy (any value works for destroy)."
  type        = string
}

variable "package_hash" {
  description = "Base64 SHA-256 of build/app.zip, as printed by scripts/build-zip.sh. A new hash makes Terraform upload the zip. No default, so pass -var package_hash=... on every apply and destroy (any value works for destroy)."
  type        = string
}

variable "origin_shield_region" {
  description = "Region for CloudFront Origin Shield, an extra cache layer; null turns it off. For eu-north-1, AWS pairs eu-west-2."
  type        = string
  default     = null
}

variable "rate_limit_all" {
  description = "Requests one IP may send in 5 minutes before getting 429. At least 10."
  type        = number
  default     = 1000

  validation {
    condition     = var.rate_limit_all >= 10
    error_message = "rate_limit_all must be at least 10."
  }
}

variable "rate_limit_create" {
  description = "Links one IP may create in 5 minutes before getting 429. At least 10."
  type        = number
  default     = 20

  validation {
    condition     = var.rate_limit_create >= 10
    error_message = "rate_limit_create must be at least 10."
  }
}

# Off for practice.
# What WAF costs: "Cost" in infra/README.md.
variable "rate_limiting" {
  description = "Rate limits (AWS WAF)."
  type        = bool
  default     = false
}

# Off at full scale, where a line for each of about 30 billion requests a month would cost thousands in CloudWatch ("Cost" in infra/README.md).
variable "cdn_access_logs" {
  description = "CloudFront's access logs (access-logs.tf): a line for each request, with its path, status and timings."
  type        = bool
  default     = true
}

# WARN at full scale, where the START, END and REPORT lines would cost thousands a month in CloudWatch.
variable "system_log_level" {
  description = "Lambda's own log lines: START, END and REPORT (with timings) for every request. INFO keeps them; WARN keeps only warnings and errors."
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["DEBUG", "INFO", "WARN"], var.system_log_level)
    error_message = "system_log_level must be DEBUG, INFO or WARN."
  }
}

# 1024 because Lambda gives CPU in proportion to memory, and the first request after a cold start is mostly CPU work (setting up the AWS SDK and the TLS connection to DynamoDB).
# Measured on cold starts in November 2026: that request took about 480 ms at 256 MB (3 cold starts) and about 130 ms at 1024 MB (11).
# Init took about 270 ms at both sizes, so more memory doesn't shorten it.
variable "memory_size" {
  description = "MB of memory for the function."
  type        = number
  default     = 1024
}

# Null for practice: Lambda only reserves concurrency that leaves at least 100 of the account's limit unreserved, and this account's limit is 10.
variable "reserved_concurrency" {
  description = "How many copies of the function may run at once; null leaves it to the account's Lambda limit."
  type        = number
  default     = null

  validation {
    condition     = var.reserved_concurrency == null ? true : var.reserved_concurrency >= 1
    error_message = "reserved_concurrency must be null or at least 1; 0 would stop the function."
  }
}
