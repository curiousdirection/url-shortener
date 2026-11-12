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
  description = "If true, no backup is taken when the database is deleted. If false, a final snapshot named <name>-final-<random> is kept and keeps costing money."
  type        = bool
  default     = true
}
