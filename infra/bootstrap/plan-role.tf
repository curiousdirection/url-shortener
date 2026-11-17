# The plan role, used by CI (.github/workflows/terraform.yml) to plan infra/app on every push.

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

# Its access key is a repository secret, so CI on any branch can use it.
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

# Read-only, enough to plan infra/app. It can't write, so CI plans with -lock=false. Any branch
# can use it, so it is denied every secret.
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
          "ecr:DescribeRepositories", "ecr:DescribeImages", "ecr:ListTagsForResource",
          "ecr:GetLifecyclePolicy", "ecs:Describe*", "ecs:List*",
          "logs:DescribeLogGroups", "logs:ListTagsForResource", "logs:ListTagsLogGroup",
        ]
        Resource = "*"
      },
      # The state bucket uses SSE-S3, so denying kms:Decrypt doesn't block state reads. Moving
      # the bucket to a KMS key would.
      {
        Effect = "Deny"
        Action = [
          "ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath",
          "ssm:GetParameterHistory", "kms:Decrypt", "secretsmanager:GetSecretValue",
        ]
        Resource = "*"
      },
    ], local.deny_statements)
  })
}
