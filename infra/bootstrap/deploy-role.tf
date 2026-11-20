# The role the deploy job runs as, and what it may do.

resource "aws_iam_role" "deploy" {
  name                 = "github-deploy-${var.name}"
  max_session_duration = 3600 # an apply can take a while

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = local.account_id
          "aws:SourceArn"     = local.runner_project_arn
        }
      }
    }]
  })
}

locals {
  function_arn  = "arn:aws:lambda:${var.region}:${local.account_id}:function:${var.name}"
  log_group_arn = "arn:aws:logs:${var.region}:${local.account_id}:log-group:/${var.name}/app"
  # The function's role, made in infra/foundation/iam.tf with this exact name.
  lambda_role_arn = "arn:aws:iam::${local.account_id}:role/${var.name}-lambda"

  runner_log_group_arn = "arn:aws:logs:${var.region}:${local.account_id}:log-group:/aws/codebuild/${local.runner_name}"
}

# Only what `terraform apply` in infra/app needs.
# It can update the function, its URL, its log group, the CDN, its web bucket, its access logs and the web ACL but not create or delete them, so a change that would replace one fails in CI instead of taking the app down.
# The exception is the CDN's response headers policy, which it can create.
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

      # The one function: update, not create or delete.
      {
        Effect = "Allow"
        Action = [
          "lambda:Get*", "lambda:List*",
          "lambda:UpdateFunctionCode", "lambda:UpdateFunctionConfiguration",
          "lambda:PutFunctionConcurrency", "lambda:DeleteFunctionConcurrency",
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
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [local.runner_log_group_arn, "${local.runner_log_group_arn}:*"]
      },
      {
        Effect   = "Allow"
        Action   = ["codeconnections:GetConnection", "codeconnections:GetConnectionToken", "codeconnections:UseConnection"]
        Resource = aws_codeconnections_connection.github.arn
      },
      ], local.cloudfront_read_statements, local.web_bucket_read_statements, local.access_log_read_statements, [
      # CloudFront's access logs: update, not create or delete.
      {
        Effect   = "Allow"
        Action   = ["logs:UpdateDeliveryConfiguration", "logs:TagResource", "logs:UntagResource"]
        Resource = local.access_log_delivery_arns
      },
      {
        Effect = "Allow"
        Action = [
          "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy", "logs:TagResource", "logs:UntagResource",
        ]
        Resource = [local.access_log_group_arn, "${local.access_log_group_arn}:*"]
      },
      # The CDN: update, not create or delete.
      # CloudFront picks the distribution's id, so it is matched by the Project tag the app stack sets.
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
      # AWS can't limit this permission to one policy, so it allows creating any response headers policy in the account.
      { Effect = "Allow", Action = "cloudfront:CreateResponseHeadersPolicy", Resource = "*" },
      {
        Effect   = "Allow"
        Action   = "cloudfront:UpdateResponseHeadersPolicy"
        Resource = "${local.cloudfront_arn}:response-headers-policy/*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudfront:UpdateFunction", "cloudfront:PublishFunction",
          "cloudfront:TagResource", "cloudfront:UntagResource",
        ]
        Resource = local.cdn_function_arn
      },
      # Clearing the page from the CDN's cache on each release (infra/scripts/release-web.sh).
      {
        Effect    = "Allow"
        Action    = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
        Resource  = "${local.cloudfront_arn}:distribution/*"
        Condition = { StringEquals = { "aws:ResourceTag/Project" = var.name } }
      },
      # The web bucket: update its settings, not create or delete it.
      {
        Effect = "Allow"
        Action = [
          "s3:PutBucketPolicy", "s3:PutBucketTagging", "s3:PutBucketPublicAccessBlock",
          "s3:PutEncryptionConfiguration",
        ]
        Resource = local.web_bucket_arn
      },
      # The page's files: upload only, no delete.
      {
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${local.web_bucket_arn}/*"
      },
      # The web ACL: update, not create or delete.
      {
        Effect   = "Allow"
        Action   = ["wafv2:UpdateWebACL", "wafv2:TagResource", "wafv2:UntagResource"]
        Resource = local.cdn_web_acl_arn
      },
    ], local.deny_statements)
  })
}
