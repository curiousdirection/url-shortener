# The CodeBuild project that runs the deploy job as a GitHub Actions runner.

locals {
  runner_name        = "${var.name}-deploy"
  runner_project_arn = "arn:aws:codebuild:${var.region}:${local.account_id}:project/${local.runner_name}"
}

resource "aws_codeconnections_connection" "github" {
  name          = "${var.name}-github"
  provider_type = "GitHub"
}

resource "aws_cloudwatch_log_group" "runner" {
  name              = "/aws/codebuild/${local.runner_name}"
  retention_in_days = 14
}

resource "aws_codebuild_project" "runner" {
  name          = local.runner_name
  description   = "Runs the deploy job of .github/workflows/ci.yml"
  service_role  = aws_iam_role.deploy.arn
  build_timeout = 60

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    type         = "LINUX_CONTAINER"
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/amazonlinux-x86_64-standard:5.0"
  }

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
      pattern = "^CI$"
    }
    filter {
      type    = "ACTOR_ACCOUNT_ID"
      pattern = "^${var.deployer_github_id}$"
    }
  }
}
