# Inputs you can change. The defaults are the practice values. To override one, put it in
# terraform.tfvars (gitignored) or pass `-var name=value`.

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

# App

variable "app_version" {
  description = "Image tag to run: the git short SHA that scripts/release.sh pushed. No default, so pass -var app_version=... on every apply and destroy (any value works for destroy)."
  type        = string
}

variable "task_cpu" {
  description = "CPU units per task: 256, 512, 1024, 2048 or 4096 (1024 = 1 vCPU). Must pair with a valid task_memory."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "MiB per task. Fargate only allows certain CPU and memory pairs (256 with 512, 2048 with 4096, ...)."
  type        = number
  default     = 512
}

variable "min_tasks" {
  description = "Fewest tasks to run."
  type        = number
  default     = 1
}

variable "max_tasks" {
  description = "Most tasks autoscaling may run (it adds tasks above 60% average CPU)."
  type        = number
  default     = 2
}

variable "alarm_email" {
  description = "Email address the alarms in alarms.tf notify. Unset: the alarms still show in the CloudWatch console but email no one."
  type        = string
  default     = null
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
