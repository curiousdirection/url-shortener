# The plan role, used by CI (.github/workflows/terraform.yml) to
# plan infra/app on every push.

resource "aws_iam_role" "plan" {
  name = "github-plan-${var.name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = aws_iam_user.plan.arn }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Its access key is a repository secret, so CI on any branch can
# use it.
resource "aws_iam_user" "plan" {
  name = "github-plan-${var.name}"
}

resource "aws_iam_user_policy" "plan_assume_role" {
  name = "assume-plan-role"
  user = aws_iam_user.plan.name
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Resource = aws_iam_role.plan.arn }]
  })
}

# Read-only, enough to plan infra/app.
# It can't write, so CI plans with -lock=false.
# Any branch can use it, so it is denied every secret (KMS
# decryption only outside Lambda, see below).
resource "aws_iam_role_policy" "plan" {
  name = "plan-read-only"
  role = aws_iam_role.plan.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      { Effect = "Allow", Action = "s3:ListBucket", Resource = local.state_arn },
      { Effect = "Allow", Action = "s3:GetObject", Resource = [local.foundation_state, local.app_state_arn] },
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups", "logs:ListTagsForResource", "logs:ListTagsLogGroup",
        ]
        Resource = "*"
      },
      # The one function: everything Terraform reads when it
      # refreshes it.
      { Effect = "Allow", Action = ["lambda:Get*", "lambda:List*"], Resource = local.function_arn },
      # The state bucket uses SSE-S3, so denying kms:Decrypt
      # doesn't block state reads.
      # Moving the bucket to a KMS key would.
      {
        Effect = "Deny"
        Action = [
          "ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath",
          "ssm:GetParameterHistory", "secretsmanager:GetSecretValue",
        ]
        Resource = "*"
      },
      # Lambda decrypts the function's environment variables for
      # the caller, and the plan needs them to plan correctly.
      # So environment variables must never hold secrets.
      {
        Effect    = "Deny"
        Action    = "kms:Decrypt"
        Resource  = "*"
        Condition = { StringNotEquals = { "kms:ViaService" = "lambda.${var.region}.amazonaws.com" } }
      },
      # The CDN: see cloudfront_read_statements in github.tf.
    ], local.cloudfront_read_statements, local.deny_statements)
  })
}
