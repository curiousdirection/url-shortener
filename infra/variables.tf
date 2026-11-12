# Inputs you can change. Every variable with a `default` is optional. To override one,
# put it in terraform.tfvars (copy terraform.tfvars.example) or pass `-var name=value`.

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

# No default on purpose: you must pass it on every `terraform apply`, so a plain apply
# can't point the servers at a release that doesn't exist.
variable "app_version" {
  description = "Release id (git short sha) uploaded by scripts/release.sh. Changing it replaces the instances. No default: pass it on every apply."
  type        = string
}

# App servers

variable "instance_type" {
  description = "EC2 instance type for the app servers. t4g.* and c7g.* are Arm (Graviton) machines; the boot script downloads the arm64 build of Node."
  type        = string
  default     = "t4g.micro"
}

variable "asg_min" {
  description = "Fewest app servers the auto scaling group keeps running."
  type        = number
  default     = 1
}

variable "asg_max" {
  description = "Most app servers the auto scaling group may scale out to."
  type        = number
  default     = 2
}

variable "asg_desired" {
  description = "Initial size only: the ASG ignores later changes so autoscaling and manual scaling are not undone."
  type        = number
  default     = 1
}

# Database

variable "db_instance_class" {
  description = "RDS machine size. db.t4g.micro is covered by the AWS free plan."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "GiB."
  type        = number
  default     = 20
}

variable "db_multi_az" {
  description = "Keep a standby copy of the database in a second availability zone for failover. Roughly doubles the cost; not allowed on the free plan."
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  description = "Days of automatic backups to keep."
  type        = number
  default     = 1
}

variable "db_deletion_protection" {
  description = "If true, AWS refuses to delete the database (including terraform destroy) until it is turned off."
  type        = bool
  default     = false
}

variable "db_apply_immediately" {
  description = "If true, database changes (such as a new instance class, which restarts it) are applied straight away. If false, they wait for the weekly maintenance window."
  type        = bool
  default     = true
}

variable "db_skip_final_snapshot" {
  description = "If true, no backup is taken when the database is deleted. If false, a final snapshot named <name>-final is kept and keeps costing money; delete it before the next destroy, or that destroy fails because the name already exists."
  type        = bool
  default     = true
}
