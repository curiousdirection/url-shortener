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

# The two roles ECS uses (see iam.tf).
output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}

output "infrastructure_role_arn" {
  value = aws_iam_role.infrastructure.arn
}

# The parameter holding the database password, for ECS to pass in as PGPASSWORD.
output "db_password_parameter_arn" {
  value = aws_ssm_parameter.db_password.arn
}

# What the app needs to build its DATABASE_URL. The password is not part of it: pg reads it
# from PGPASSWORD.
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
