# How GitHub Actions signs in to AWS. Each of the two roles has its own IAM user, whose only
# permission is to assume that role. The workflow signs in with the user's access key (a GitHub
# secret) and assumes the role, so jobs run on credentials that expire within an hour. Why
# keys and not OIDC: docs/decisions/0004-access-keys-instead-of-oidc.md.
#
# The keys are not made here, so they stay out of the state; see "Set up and first run" in
# ../README.md.
#
# Two roles: the deploy role (deploy-role.tf) applies infra/app; the plan role (plan-role.tf)
# is read-only, for CI on any branch. Neither can change IAM or this stack.

locals {
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
