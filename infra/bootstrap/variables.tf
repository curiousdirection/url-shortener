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
