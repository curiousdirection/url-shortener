# Inputs you can change.
# The defaults are the practice values.
# To override one, put it in terraform.tfvars (gitignored) or pass `-var name=value`.
# The function's own settings (memory) are in infra/app/variables.tf.

variable "name" {
  description = "Prefix for resource names and tags."
  type        = string
  default     = "url-shortener"
}

# A project account is fixed to the region AWS assigned it (eu-north-1 for Europe); check AWS Settings > Project.
variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-north-1"
}

# Table

variable "table_point_in_time_recovery" {
  description = "Keep continuous backups, so the table can be restored to any second in the last 35 days. Costs a little per GB stored."
  type        = bool
  default     = false
}

variable "table_deletion_protection" {
  description = "If true, AWS refuses to delete the table (including terraform destroy) until it is turned off."
  type        = bool
  default     = false
}

# Alarms

# Required, with no default: an alarm that emails no one fails silently, so a missing address stops the plan instead.
variable "alarm_email" {
  description = "Email address the alarms are sent to. Kept out of git: set it in infra/foundation/terraform.tfvars."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+$", var.alarm_email))
    error_message = "alarm_email must be an email address."
  }
}
