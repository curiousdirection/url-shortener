# Printed after `terraform apply`.
# Show them again with `terraform output`.
# None are secret.

# Put this in infra/backend.hcl, in `state_bucket` in infra/app/terraform.tfvars and in the TF_STATE_BUCKET GitHub variable.
output "state_bucket" {
  value = aws_s3_bucket.state.bucket
}

output "region" {
  value = var.region
}
