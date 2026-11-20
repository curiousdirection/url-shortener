# The CodeBuild project that hosts the runner for the deploy job of .github/workflows/deploy.yml.
# CodeBuild starts one runner per queued job, and the job gets the deploy role's credentials from the project's service role, so CI holds no AWS keys.
# Why: docs/decisions/0011-deploy-on-a-codebuild-runner.md.

locals {
  # The name is also in the `runs-on` of .github/workflows/deploy.yml.
  runner_name = "${var.name}-deploy"
  # Built from the name, not from the project, because the deploy role's trust policy needs it and the project needs the role.
  runner_project_arn = "arn:aws:codebuild:${var.region}:${local.account_id}:project/${local.runner_name}"
}

# Created "pending": approve it once in the console, which installs the AWS GitHub App ("Set up and first run" in infra/README.md).
resource "aws_codeconnections_connection" "github" {
  name          = "${var.name}-github"
  provider_type = "GitHub"
}

# Kept short, since a build log is a copy of the job's log in GitHub.
resource "aws_cloudwatch_log_group" "runner" {
  name              = "/aws/codebuild/${local.runner_name}"
  retention_in_days = 14
}

resource "aws_codebuild_project" "runner" {
  name          = local.runner_name
  description   = "Runs the deploy job of .github/workflows/deploy.yml"
  service_role  = aws_iam_role.deploy.arn
  build_timeout = 60 # minutes, more than the job's timeout-minutes, so the job times out first

  # The buildspec is ignored for a runner, and nothing is kept.
  artifacts {
    type = "NO_ARTIFACTS"
  }

  # General1.small: the free tier is 100 build minutes a month.
  # Amazon Linux 2023, the newest standard image the runner docs list.
  environment {
    type         = "LINUX_CONTAINER"
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/amazonlinux-x86_64-standard:5.0"
  }

  # The connection is set on the project, so the account's default GitHub credential in CodeBuild is left alone.
  source {
    type     = "GITHUB"
    location = "https://github.com/${var.github_repo}"
    auth {
      type     = "CODECONNECTIONS"
      resource = aws_codeconnections_connection.github.arn
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.runner.name
    }
  }
}

# Starts a runner for each queued job of a workflow named "Deploy" that the deployer's GitHub account triggered.
# CodeBuild can't filter a runner job by branch: see "Access to AWS" in docs/security.md.
resource "aws_codebuild_webhook" "runner" {
  project_name = aws_codebuild_project.runner.name
  build_type   = "BUILD"

  filter_group {
    filter {
      type    = "EVENT"
      pattern = "WORKFLOW_JOB_QUEUED"
    }
    filter {
      type    = "WORKFLOW_NAME"
      pattern = "^Deploy$"
    }
    # Matches the `id` of the webhook payload's `sender`:
    # https://docs.aws.amazon.com/codebuild/latest/userguide/github-webhook.html
    # Anchored, because an unanchored pattern let other accounts through in:
    # https://aws.amazon.com/security/security-bulletins/2026-002-AWS/
    filter {
      type    = "ACTOR_ACCOUNT_ID"
      pattern = "^${var.deployer_github_id}$"
    }
  }
}
