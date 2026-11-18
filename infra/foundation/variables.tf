# Inputs you can change. The defaults are the practice values. To override one, put it in
# terraform.tfvars (gitignored) or pass `-var name=value`. The function's own settings (memory)
# are in ../app/variables.tf.

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
