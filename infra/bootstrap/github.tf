# How GitHub Actions signs in to AWS without stored keys: each run gets a signed token from
# GitHub (OIDC), and a role's trust policy says which tokens may assume it.
#   https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
#
# Two roles: the deploy role (production environment on main) applies infra/app; the plan role
# (pull requests) is read-only. Neither can change IAM or this stack.

locals {
  # The start of the token's `sub` claim. Repositories created or renamed after 15 July 2026
  # use an ID-based form; see github_oidc_sub_prefix.
  #   https://docs.github.com/en/actions/reference/security/oidc
  sub_repo = var.github_oidc_sub_prefix != "" ? var.github_oidc_sub_prefix : "repo:${var.github_repository}"

  # Where the Terraform state is (see state.tf). The app state is the only one CI may change.
  state_arn         = aws_s3_bucket.state.arn
  app_state_arn     = "${local.state_arn}/app/terraform.tfstate"
  app_lock_arn      = "${local.state_arn}/app/terraform.tfstate.tflock"
  foundation_state  = "${local.state_arn}/foundation/terraform.tfstate"
  bootstrap_objects = "${local.state_arn}/bootstrap/*"

  account_id = data.aws_caller_identity.current.account_id

  # The two roles ECS uses (made in infra/foundation/iam.tf, with these exact names).
  execution_role_arn      = "arn:aws:iam::${local.account_id}:role/${var.name}-execution"
  infrastructure_role_arn = "arn:aws:iam::${local.account_id}:role/${var.name}-infrastructure"

  ecr_repository_arn = "arn:aws:ecr:${var.region}:${local.account_id}:repository/${var.name}"
  log_group_arn      = "arn:aws:logs:${var.region}:${local.account_id}:log-group:/${var.name}/app"

  # Explicit denies for both roles: they hold even if an allow is widened by mistake.
  deny_statements = [
    {
      Sid    = "NoIamChanges"
      Effect = "Deny"
      Action = [
        "iam:Add*", "iam:Attach*", "iam:Create*", "iam:Delete*", "iam:Detach*", "iam:Put*",
        "iam:Remove*", "iam:Set*", "iam:Tag*", "iam:Untag*", "iam:Update*", "iam:Upload*",
      ]
      Resource = "*"
    },
    {
      Sid      = "NoBootstrapState"
      Effect   = "Deny"
      Action   = "s3:*"
      Resource = local.bootstrap_objects
    },
  ]
}

# ---------------------------------------------------------------------------------------------
# The OIDC provider
# ---------------------------------------------------------------------------------------------

# An AWS account can only have one provider for GitHub. If yours already has one, set
# create_github_oidc_provider = false and it is looked up instead.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url = "https://token.actions.githubusercontent.com"
  # The audience the tokens are for. configure-aws-credentials asks for this one.
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1

  url = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

# ---------------------------------------------------------------------------------------------
# The deploy role: used by .github/workflows/deploy.yml, to apply infra/app
# ---------------------------------------------------------------------------------------------

resource "aws_iam_role" "deploy" {
  name = "github-deploy-${var.name}"
  # A deploy can run long (the apply waits for the release to go live).
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "${local.sub_repo}:environment:${var.github_environment}"
          # A second lock besides the environment's branch rule, as AWS recommends.
          "token.actions.githubusercontent.com:ref" = "refs/heads/main"
        }
      }
    }]
  })
}

# Only what the image push and `terraform apply` in infra/app need. It can update the service
# but not create or delete it, so a change that would replace the service fails in CI instead
# of taking the app down. Not yet run against a real account: add any action the first run
# is refused.
resource "aws_iam_role_policy" "deploy" {
  name = "deploy-app-stack"
  role = aws_iam_role.deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      # --- Terraform state --------------------------------------------------------------
      # The app state and its lock file only.
      {
        Sid      = "StateBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = local.state_arn
      },
      {
        Sid      = "AppState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = [local.app_state_arn, local.app_lock_arn]
      },
      # The app stack reads the foundation outputs. Read only.
      {
        Sid      = "FoundationStateRead"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = local.foundation_state
      },

      # --- Container images -------------------------------------------------------------
      # The login token is not tied to a repository.
      {
        Sid      = "EcrLogin"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      # The one repository: push, read and update settings. Not create or delete.
      {
        Sid    = "EcrRepository"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer", "ecr:DescribeImages", "ecr:ListImages",
          "ecr:DescribeRepositories", "ecr:ListTagsForResource", "ecr:GetLifecyclePolicy",
          "ecr:PutLifecyclePolicy", "ecr:TagResource", "ecr:UntagResource",
        ]
        Resource = local.ecr_repository_arn
      },

      # --- The ECS Express Mode service -------------------------------------------------
      # Express Mode builds the rest itself, with the infrastructure role. These actions don't
      # support narrower resources than "*".
      #   https://aws.amazon.com/blogs/containers/automated-deployments-with-github-actions-for-amazon-ecs-express-mode/
      {
        Sid    = "EcsExpressService"
        Effect = "Allow"
        Action = [
          "ecs:DescribeExpressGatewayService", "ecs:UpdateExpressGatewayService",
          "ecs:DescribeServices", "ecs:UpdateService", "ecs:DescribeServiceRevisions",
          "ecs:DescribeServiceDeployments", "ecs:ListServiceDeployments",
          "ecs:DescribeClusters", "ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition",
          "ecs:DescribeTasks", "ecs:ListTasks", "ecs:ListTagsForResource",
          "ecs:TagResource", "ecs:UntagResource",
        ]
        Resource = "*"
      },
      # The one IAM permission a deploy needs: handing the two foundation roles to ECS.
      {
        Sid      = "PassEcsRoles"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = [local.execution_role_arn, local.infrastructure_role_arn]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = ["ecs.amazonaws.com", "ecs-tasks.amazonaws.com"]
          }
        }
      },

      # --- The log group ----------------------------------------------------------------
      {
        Sid      = "LogGroupList"
        Effect   = "Allow"
        Action   = "logs:DescribeLogGroups"
        Resource = "arn:aws:logs:${var.region}:${local.account_id}:log-group:*"
      },
      {
        Sid    = "LogGroupManage"
        Effect = "Allow"
        Action = [
          "logs:ListTagsForResource", "logs:ListTagsLogGroup", "logs:PutRetentionPolicy",
          "logs:DeleteRetentionPolicy", "logs:TagResource", "logs:UntagResource",
        ]
        Resource = [local.log_group_arn, "${local.log_group_arn}:*"]
      },
    ], local.deny_statements)
  })
}

# ---------------------------------------------------------------------------------------------
# The plan role: used by .github/workflows/ci.yml, to show plans on pull requests
# ---------------------------------------------------------------------------------------------

resource "aws_iam_role" "plan" {
  name = "github-plan-${var.name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          # Any pull request in this repository. (Pull requests from forks get no token.)
          "token.actions.githubusercontent.com:sub" = "${local.sub_repo}:pull_request"
        }
      }
    }]
  })
}

# Read-only, enough to plan infra/app. It can't write, so CI plans with -lock=false. It is
# denied every secret: any pull request can use it, which is also why CI never plans the
# foundation (refreshing it would decrypt the database password).
resource "aws_iam_role_policy" "plan" {
  name = "plan-read-only"
  role = aws_iam_role.plan.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid      = "StateBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = local.state_arn
      },
      {
        Sid      = "ReadBothStates"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = [local.foundation_state, local.app_state_arn]
      },
      # Look at what the app stack manages. Describe and List calls only.
      {
        Sid    = "ReadAppResources"
        Effect = "Allow"
        Action = [
          "ecr:DescribeRepositories", "ecr:DescribeImages", "ecr:ListTagsForResource",
          "ecr:GetLifecyclePolicy",
          "ecs:Describe*", "ecs:List*",
          "logs:DescribeLogGroups", "logs:ListTagsForResource", "logs:ListTagsLogGroup",
        ]
        Resource = "*"
      },
      # The state bucket uses SSE-S3, so denying kms:Decrypt doesn't block state reads. Moving
      # the bucket to a KMS key would.
      {
        Sid    = "NoSecrets"
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
