variable "name" {
  description = "Prefix for resource names and tags."
  type        = string
  default     = "url-shortener"
}

variable "region" {
  description = "AWS region. A project account is fixed to the region AWS assigned it (eu-north-1 for Europe); check AWS Settings > Project."
  type        = string
  default     = "eu-north-1"
}

variable "app_version" {
  description = "Release id (git short sha) uploaded by scripts/release.sh. Changing it replaces the instances. No default: pass it on every apply."
  type        = string
}

variable "domain_name" {
  description = "Optional. If set (together with route53_zone_id), the NLB also serves TLS on :443 for this name and BASE_URL becomes https://<domain_name>."
  type        = string
  default     = null
}

variable "route53_zone_id" {
  description = "Hosted zone that holds domain_name. Used for ACM DNS validation and the alias record."
  type        = string
  default     = null

  validation {
    condition     = var.domain_name == null || var.route53_zone_id != null
    error_message = "domain_name needs route53_zone_id too (used for DNS validation and the alias record)."
  }
}

variable "budget_alert_email" {
  description = "Where budget alerts go. Set it in terraform.tfvars, which is gitignored."
  type        = string
}

variable "budget_limit_usd" {
  description = "Monthly cost limit for the budget alert."
  type        = string
  default     = "10"
}

# App servers

variable "instance_type" {
  type    = string
  default = "t4g.micro"
}

variable "asg_min" {
  type    = number
  default = 1
}

variable "asg_max" {
  type    = number
  default = 2
}

variable "asg_desired" {
  description = "Initial size only: the ASG ignores later changes so autoscaling and manual scaling are not undone."
  type        = number
  default     = 1
}

# Database

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "GiB."
  type        = number
  default     = 20
}

variable "db_multi_az" {
  type    = bool
  default = false
}

variable "db_backup_retention_days" {
  type    = number
  default = 1
}

variable "db_deletion_protection" {
  type    = bool
  default = false
}

variable "db_skip_final_snapshot" {
  type    = bool
  default = true
}
