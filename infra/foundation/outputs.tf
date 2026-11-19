# Values the app stack reads (with terraform_remote_state) to wire the function to this foundation.
# They are not secret.
# You can see them any time with `terraform output`.

# The table's name, which the function gets as TABLE_NAME.
output "table_name" {
  value = aws_dynamodb_table.urls.name
}

# The role the function runs as (see iam.tf).
output "lambda_role_arn" {
  value = aws_iam_role.lambda.arn
}
