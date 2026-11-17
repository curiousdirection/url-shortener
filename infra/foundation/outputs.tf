# Values the app stack reads (with terraform_remote_state) to wire the service to this
# foundation. They are not secret. You can see them any time with `terraform output`.

# Where the app tasks run: the public subnets (Express Mode needs at least two).
output "public_subnet_ids" {
  value = module.vpc.public_subnets
}

# Attached to the app tasks; the database accepts connections from this group.
output "app_security_group_id" {
  value = aws_security_group.app.id
}

# The roles ECS uses (see iam.tf).
output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}

output "infrastructure_role_arn" {
  value = aws_iam_role.infrastructure.arn
}

# For infra/scripts/setup-db.sh, the one-off task that creates the app's database user: its
# execution role, and the parameter with the password it reads.
output "db_setup_execution_role_arn" {
  value = aws_iam_role.db_setup_execution.arn
}

output "db_password_parameter_arn" {
  value = aws_ssm_parameter.db_password.arn
}

# What the app and the setup task need to build their DATABASE_URL. The master username is
# only for the setup task; the app logs in as `app`.
output "db_address" {
  value = aws_db_instance.main.address
}

output "db_name" {
  value = aws_db_instance.main.db_name
}

output "db_username" {
  value = aws_db_instance.main.username
}

# The database's address and port. It is only reachable from inside the VPC.
output "rds_endpoint" {
  value = aws_db_instance.main.endpoint
}
