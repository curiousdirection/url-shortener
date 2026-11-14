# Inputs you can change. The defaults are the practice values. To override one, put it in
# terraform.tfvars (gitignored) or pass `-var name=value`. The database settings are in
# ../foundation/variables.tf.

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

variable "app_version" {
  description = "Image tag to run: the git short SHA (7 characters) that scripts/release.sh or the deploy workflow pushed. No default, so pass -var app_version=... on every apply and destroy (any value works for destroy)."
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
