# How GitHub Actions signs in to AWS, without any stored access keys.
#
# GitHub gives each workflow run a short-lived signed token ("OIDC token") that says which
# repository, branch and environment the run is for. AWS is told to trust GitHub's signature
# (the OIDC provider below), and each IAM role says which tokens may assume it (its "trust
# policy"). The workflow trades its token for temporary AWS credentials.
#   https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
#
# Two roles, so that a pull request can only look and never change anything:
#
#   github-deploy-url-shortener  deploys the app. Only the `production` environment of this
#                                repository can assume it, and (in GitHub) that environment
#                                only accepts the main branch.
#   github-plan-url-shortener    shows what a change would do. Any pull request of this
#                                repository can assume it. Read-only.
#
# Neither role can create or change IAM roles or policies (so they can't change themselves or
# each other), and neither can touch this bootstrap stack or its state.

locals {
  # The start of the `sub` claim in GitHub's tokens. Classic form: repo:owner/name.
  #
  # Heads up: GitHub repositories created or renamed after 15 July 2026 emit an ID-based sub
  # (repo:owner@<owner id>/name@<repo id>) instead. If this repository gets it, AWS answers
  # "Not authorized to perform sts:AssumeRoleWithWebIdentity" on the first run: set
  # github_oidc_sub_prefix to what the workflow log shows and apply this stack again.
  # GitHub's page does not show the environment and pull_request forms for the ID-based sub,
  # so check them on the first run.
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

  # Explicit "no" for both roles. A deny beats any allow, so even if someone adds a broad
  # permission to a role by mistake, these still hold.
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
          # Only jobs that run in the `production` environment of this repository...
          "token.actions.githubusercontent.com:sub" = "${local.sub_repo}:environment:${var.github_environment}"
          # ...and only on main (a second lock; the environment in GitHub also allows only
          # main). AWS's guidance for environment-based trust is to add this.
          "token.actions.githubusercontent.com:ref" = "refs/heads/main"
        }
      }
    }]
  })
}

# What the deploy role may do: exactly what `terraform apply` in infra/app and the image push
# need, and nothing for the network, the database or IAM. It can UPDATE the service but not
# create or delete it: creating it again is a job for a person (release.sh), and a change that
# would replace the service fails in CI instead of taking the app down.
#
# These lists are written from the AWS docs and the provider docs, and have not been run
# against a real account. If the first run says "not authorized to perform <action>", add that
# action here (see "First run" in infra/README.md).
resource "aws_iam_role_policy" "deploy" {
  name = "deploy-app-stack"
  role = aws_iam_role.deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      # --- Terraform state --------------------------------------------------------------
      # The S3 backend lists the bucket, then reads, writes and deletes the state and its
      # lock file for the app stack only.
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
      # Push and look up images in the one repository, and let Terraform read and update the
      # repository's settings and lifecycle policy. (Not create or delete the repository.)
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
      # Express Mode builds the load balancer, certificate and autoscaling itself, with the
      # infrastructure role. The caller only needs the ECS actions below. They don't support
      # narrower resources than "*" for the cluster and task definitions.
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
      # Handing the two foundation roles to ECS is not "changing" them, but it is the one
      # IAM permission a deploy needs. Only these two roles, and only to ECS.
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

# Read-only, for the app stack only. It can read both state files (the app stack reads the
# foundation's outputs) and look at what the app stack manages, so that `terraform plan` works
# for `infra/app`. It can't write anything, which is why CI runs the plan with -lock=false
# (taking the lock would write a file).
#
# There is no foundation plan on pull requests: refreshing the database password parameter
# would mean decrypting it, and any pull request can use this role. So this role is denied the
# parameter and KMS decryption outright. You plan the foundation yourself before applying it.
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
      # A deny wins over any allow, so this holds even if an allow above is widened later.
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
