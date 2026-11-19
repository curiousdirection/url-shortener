# How GitHub Actions signs in to AWS.
# Each of the two roles has its own IAM user, whose only
# permission is to assume that role.
# The workflow signs in with the user's access key (a GitHub
# secret) and assumes the role, so jobs run on credentials that
# expire within an hour.
# Why keys and not OIDC:
# docs/decisions/0004-access-keys-instead-of-oidc.md.
#
# The keys are not made here, so they stay out of the state; see
# "Set up and first run" in infra/README.md.
#
# Two roles: the deploy role (deploy-role.tf) applies infra/app;
# the plan role (plan-role.tf) is read-only, for CI on any
# branch.
# Neither can change IAM or this stack.

locals {
  account_id       = data.aws_caller_identity.current.account_id
  state_arn        = aws_s3_bucket.state.arn
  app_state_arn    = "${local.state_arn}/app/terraform.tfstate"
  foundation_state = "${local.state_arn}/foundation/terraform.tfstate"

  cloudfront_arn = "arn:aws:cloudfront::${local.account_id}"
  # The CDN's function, made in infra/app/cdn.tf with this exact
  # name.
  cdn_function_arn = "${local.cloudfront_arn}:function/${var.name}-forwarded-host"

  cdn_web_acl_arn = "arn:aws:wafv2:us-east-1:${local.account_id}:global/webacl/${var.name}/*"

  # What Terraform reads to refresh the CDN, for both roles.
  # CloudFront picks the ids, hence `*`.
  cloudfront_read_statements = [
    {
      Effect   = "Allow"
      Action   = ["cloudfront:GetDistribution", "cloudfront:GetDistributionConfig"]
      Resource = "${local.cloudfront_arn}:distribution/*"
    },
    {
      Effect   = "Allow"
      Action   = ["cloudfront:GetOriginAccessControl", "cloudfront:GetOriginAccessControlConfig"]
      Resource = "${local.cloudfront_arn}:origin-access-control/*"
    },
    {
      Effect   = "Allow"
      Action   = ["cloudfront:DescribeFunction", "cloudfront:GetFunction"]
      Resource = local.cdn_function_arn
    },
    {
      Effect   = "Allow"
      Action   = "cloudfront:ListTagsForResource"
      Resource = ["${local.cloudfront_arn}:distribution/*", local.cdn_function_arn]
    },
    # AWS's ready-made cache and origin request policies, which
    # cdn.tf looks up by name.
    {
      Effect = "Allow"
      Action = [
        "cloudfront:ListCachePolicies", "cloudfront:GetCachePolicy",
        "cloudfront:ListOriginRequestPolicies", "cloudfront:GetOriginRequestPolicy",
      ]
      Resource = "*"
    },
    # The web ACL, in us-east-1.
    # WAF adds an id after the name, hence `*`.
    {
      Effect   = "Allow"
      Action   = ["wafv2:GetWebACL", "wafv2:ListTagsForResource"]
      Resource = local.cdn_web_acl_arn
    },
  ]

  # Explicit denies for both roles: they hold even if an allow is
  # widened by mistake.
  deny_statements = [
    {
      Effect = "Deny"
      Action = [
        "iam:Add*", "iam:Attach*", "iam:Create*", "iam:Delete*", "iam:Detach*", "iam:Put*",
        "iam:Remove*", "iam:Set*", "iam:Tag*", "iam:Untag*", "iam:Update*", "iam:Upload*",
      ]
      Resource = "*"
    },
    {
      Effect   = "Deny"
      Action   = "s3:*"
      Resource = "${local.state_arn}/bootstrap/*"
    },
  ]
}
