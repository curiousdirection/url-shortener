# The deploy role, used by .github/workflows/deploy.yml to push the image and apply infra/app.

resource "aws_iam_role" "deploy" {
  name                 = "github-deploy-${var.name}"
  max_session_duration = 3600 # the apply waits for the release to go live

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
  ecr_repository_arn = "arn:aws:ecr:${var.region}:${local.account_id}:repository/${var.name}"
  log_group_arn      = "arn:aws:logs:${var.region}:${local.account_id}:log-group:/${var.name}/app"
  # The roles ECS uses for the service, made in infra/foundation/iam.tf with these exact names.
  # Not the setup task's execution role: CI must not be able to run a task that reads the
  # database password.
  ecs_role_arns = [
    "arn:aws:iam::${local.account_id}:role/${var.name}-execution",
    "arn:aws:iam::${local.account_id}:role/${var.name}-task",
    "arn:aws:iam::${local.account_id}:role/${var.name}-infrastructure",
  ]
}

# Only what the image push and `terraform apply` in infra/app need. It can update the service
# but not create or delete it, so a change that would replace the service fails in CI instead
# of taking the app down.
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

      # Images: the login token isn't tied to a repository. Then the one repository: push,
      # read and update settings. Not create or delete.
      { Effect = "Allow", Action = "ecr:GetAuthorizationToken", Resource = "*" },
      {
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

      # The Express service. Express Mode builds the rest itself, with the infrastructure role.
      # These actions don't support narrower resources than "*".
      #   https://aws.amazon.com/blogs/containers/automated-deployments-with-github-actions-for-amazon-ecs-express-mode/
      {
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
      # The one IAM permission a deploy needs: handing the three ECS roles to ECS.
      {
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = local.ecs_role_arns
        Condition = { StringEquals = { "iam:PassedToService" = ["ecs.amazonaws.com", "ecs-tasks.amazonaws.com"] } }
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
    ], local.deny_statements)
  })
}
