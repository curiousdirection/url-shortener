# The deploy role, used by .github/workflows/deploy.yml to apply infra/app.

resource "aws_iam_role" "deploy" {
  name                 = "github-deploy-${var.name}"
  max_session_duration = 3600 # an apply can take a while

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = aws_iam_user.deploy.arn }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Its access key is only given to the `production` environment, which only main can use.
resource "aws_iam_user" "deploy" {
  name = "github-deploy-${var.name}"
}

resource "aws_iam_user_policy" "deploy_assume_role" {
  name = "assume-deploy-role"
  user = aws_iam_user.deploy.name
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Resource = aws_iam_role.deploy.arn }]
  })
}

locals {
  function_arn  = "arn:aws:lambda:${var.region}:${local.account_id}:function:${var.name}"
  log_group_arn = "arn:aws:logs:${var.region}:${local.account_id}:log-group:/${var.name}/app"
  # The function's role, made in infra/foundation/iam.tf with this exact name.
  lambda_role_arn = "arn:aws:iam::${local.account_id}:role/${var.name}-lambda"
}

# Only what `terraform apply` in infra/app needs. It can update the function, its URL, its log group and the CDN
# but not create or delete them, so a change that would replace the function fails in
# CI instead of taking the app down.
resource "aws_iam_role_policy" "deploy" {
  name = "deploy-app-stack"
  role = aws_iam_role.deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      # State: the app state and its lock file; the foundation state read-only.
      { Effect = "Allow", Action = "s3:ListBucket", Resource = local.state_arn },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = [local.app_state_arn, "${local.app_state_arn}.tflock"]
      },
      { Effect = "Allow", Action = "s3:GetObject", Resource = local.foundation_state },

      # The one function: read everything Terraform refreshes, and change its code, settings,
      # URL settings, invoke permissions and tags.
      {
        Effect = "Allow"
        Action = [
          "lambda:Get*", "lambda:List*",
          "lambda:UpdateFunctionCode", "lambda:UpdateFunctionConfiguration",
          "lambda:UpdateFunctionUrlConfig", "lambda:AddPermission", "lambda:RemovePermission",
          "lambda:TagResource", "lambda:UntagResource",
        ]
        Resource = local.function_arn
      },
      # The one IAM permission a deploy needs: handing the function's role to Lambda.
      {
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = local.lambda_role_arn
        Condition = { StringEquals = { "iam:PassedToService" = "lambda.amazonaws.com" } }
      },

      # The log group.
      {
        Effect   = "Allow"
        Action   = "logs:DescribeLogGroups"
        Resource = "arn:aws:logs:${var.region}:${local.account_id}:log-group:*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:ListTagsForResource", "logs:ListTagsLogGroup", "logs:PutRetentionPolicy",
          "logs:DeleteRetentionPolicy", "logs:TagResource", "logs:UntagResource",
        ]
        Resource = [local.log_group_arn, "${local.log_group_arn}:*"]
      },
      ], local.cloudfront_read_statements, [
      # The CDN (infra/app/cdn.tf): change its settings, but not create or delete it, like the
      # function. The distribution's id is made up by CloudFront, so it is matched by the
      # Project tag that the app stack puts on everything.
      {
        Effect    = "Allow"
        Action    = ["cloudfront:UpdateDistribution", "cloudfront:TagResource", "cloudfront:UntagResource"]
        Resource  = "${local.cloudfront_arn}:distribution/*"
        Condition = { StringEquals = { "aws:ResourceTag/Project" = var.name } }
      },
      {
        Effect   = "Allow"
        Action   = "cloudfront:UpdateOriginAccessControl"
        Resource = "${local.cloudfront_arn}:origin-access-control/*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudfront:UpdateFunction", "cloudfront:PublishFunction",
          "cloudfront:TagResource", "cloudfront:UntagResource",
        ]
        Resource = local.cdn_function_arn
      },
    ], local.deny_statements)
  })
}
