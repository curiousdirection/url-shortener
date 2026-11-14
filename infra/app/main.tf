# The app: a container image in ECR, run by an ECS Express Mode service.
#
# The network, the database, the security groups, the two IAM roles and the database password
# come from the foundation stack (see the data source below).
#
# Express Mode creates the rest: the ECS cluster ("default"), task definition, an
# internet-facing load balancer with HTTPS and a certificate, target group, its own security
# groups and CPU autoscaling.
#   https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-work.html

# What the foundation stack created, read from its state in S3. If this fails with "no
# outputs", the foundation stack has not been applied yet: do that first (see "Deploy" in
# ../README.md).
#
# The state bucket is named by ../bootstrap: <name>-tfstate-<account id>.
data "aws_caller_identity" "current" {}

data "terraform_remote_state" "foundation" {
  backend = "s3"
  config = {
    bucket = "${var.name}-tfstate-${data.aws_caller_identity.current.account_id}"
    key    = "foundation/terraform.tfstate"
    region = var.region
  }
}

locals {
  foundation = data.terraform_remote_state.foundation.outputs
}

resource "aws_ecr_repository" "app" {
  name = var.name
  # A tag, once pushed, always means the same image (release.sh tags with the git SHA).
  image_tag_mutability = "IMMUTABLE"
  # Otherwise terraform destroy fails while images are still in the repository.
  force_delete = true
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 10 images (the ones you can roll back to)"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 }
      action       = { type = "expire" }
    }]
  })
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.name}/app"
  retention_in_days = 7
}

resource "aws_ecs_express_gateway_service" "app" {
  service_name            = var.name
  execution_role_arn      = local.foundation.execution_role_arn
  infrastructure_role_arn = local.foundation.infrastructure_role_arn

  # Graviton (Arm): cheaper than x86. scripts/release.sh builds the image for linux/arm64.
  cpu_architecture  = "ARM64"
  cpu               = tostring(var.task_cpu)
  memory            = tostring(var.task_memory)
  health_check_path = "/health"

  # Make apply wait for the deployment, and fail if Express Mode rolls it back.
  wait_for_steady_state = true

  network_configuration {
    subnets         = local.foundation.public_subnet_ids
    security_groups = [local.foundation.app_security_group_id]
  }

  scaling_target {
    auto_scaling_metric = "AVERAGE_CPU"
    # Express Mode's default, set explicitly: left out, the provider fails after creating
    # the service ("produced an unexpected new value").
    auto_scaling_target_value = 60
    min_task_count            = var.min_tasks
    max_task_count            = var.max_tasks
  }

  primary_container {
    image          = "${aws_ecr_repository.app.repository_url}:${var.app_version}"
    container_port = 3000 # the app's default PORT

    aws_logs_configuration {
      log_group = aws_cloudwatch_log_group.app.name
      # The provider docs call this optional, but the AWS API rejects the service without it.
      log_stream_prefix = "ecs"
    }

    # pg reads PGPASSWORD itself (see src/db.ts). verify-full checks the server certificate and
    # its name against the RDS CA bundle in the image.
    environment {
      name  = "DATABASE_URL"
      value = "postgres://${local.foundation.db_username}@${local.foundation.db_address}:5432/${local.foundation.db_name}?sslmode=verify-full"
    }
    secret {
      name       = "PGPASSWORD"
      value_from = local.foundation.db_password_parameter_arn
    }
  }

  # No depends_on for the roles' policies or the DB rule: they are in the foundation stack,
  # which is applied first and destroyed last (see "Tear down" in ../README.md). Destroying
  # the foundation while this service exists would leave the service stuck in DRAINING.
}
