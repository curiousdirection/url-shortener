# Inputs you can change. The defaults are the practice values. To override one, put it in
# terraform.tfvars (gitignored) or pass `-var name=value`. The table settings are in
# ../foundation/variables.tf. `state_bucket` has no default: you must set it (see below).

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
  description = "Turn on CloudFront Origin Shield in this region, an extra cache layer in front of the function (see \"Cost\" in infra/README.md). null turns it off. Use the nearest region that has it: for a function in eu-north-1 that is eu-west-2, per https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/origin-shield.html."
  type        = string
  default     = null
}

variable "memory_size" {
  description = "MB of memory for the function. Lambda gives CPU in proportion, so more memory is also faster."
  type        = number
  default     = 256
}
