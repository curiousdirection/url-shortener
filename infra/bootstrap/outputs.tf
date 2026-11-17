# Printed after `terraform apply`. Show them again with `terraform output`. None are secret.

# Put this in infra/backend.hcl, in `state_bucket` in infra/app/terraform.tfvars and in the
# TF_STATE_BUCKET GitHub variable.
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

output "region" {
  value = var.region
}
