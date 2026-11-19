# Printed after `terraform apply`.
# Show them again with `terraform output`.
# None are secret.

# Put this in infra/backend.hcl, in `state_bucket` in infra/app/terraform.tfvars and in the TF_STATE_BUCKET GitHub variable.
output "state_bucket" {
  value = aws_s3_bucket.state.bucket
}

# Put this in the AWS_DEPLOY_ROLE_ARN GitHub variable.
output "deploy_role_arn" {
  value = aws_iam_role.deploy.arn
}

# Put this in the AWS_PLAN_ROLE_ARN GitHub variable.
output "plan_role_arn" {
  value = aws_iam_role.plan.arn
}

# The IAM users to make the access keys for (see "Set up and first run" in infra/README.md).
output "deploy_user_name" {
  value = aws_iam_user.deploy.name
}

output "plan_user_name" {
  value = aws_iam_user.plan.name
}

output "region" {
  value = var.region
}
