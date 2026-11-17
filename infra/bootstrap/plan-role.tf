# The plan role, used by CI (.github/workflows/terraform.yml) to plan infra/app on every push.

resource "aws_iam_role" "plan" {
  name = "github-plan-${var.name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        # A push to any branch of this repository.
        StringLike = { "token.actions.githubusercontent.com:sub" = "${local.sub_repo}:ref:refs/heads/*" }
      }
    }]
  })
}

# Read-only, enough to plan infra/app. It can't write, so CI plans with -lock=false. It is
# denied every secret: any branch can use it, which is also why CI never plans the
# foundation (refreshing it would decrypt the database password).
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
