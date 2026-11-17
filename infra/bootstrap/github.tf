# How GitHub Actions signs in to AWS without stored keys: each run gets a signed token from
# GitHub (OIDC), and a role's trust policy says which tokens may assume it.
#   https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
#
# Two roles: the deploy role (deploy-role.tf) applies infra/app; the plan role (plan-role.tf)
# is read-only, for CI on any branch. Neither can change IAM or this stack.

# An AWS account can only have one provider for GitHub. If yours already has one, set
# create_github_oidc_provider = false and it is looked up instead.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1

  url = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn

  # The start of the token's `sub` claim; see github_oidc_sub_prefix.
  sub_repo = var.github_oidc_sub_prefix != "" ? var.github_oidc_sub_prefix : "repo:${var.github_repository}"

  account_id       = data.aws_caller_identity.current.account_id
  state_arn        = aws_s3_bucket.state.arn
  app_state_arn    = "${local.state_arn}/app/terraform.tfstate"
  foundation_state = "${local.state_arn}/foundation/terraform.tfstate"

  # Explicit denies for both roles: they hold even if an allow is widened by mistake.
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
