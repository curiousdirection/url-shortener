# The app: a container image in ECR, run by an ECS Express Mode service.
#
# Express Mode creates the rest: the ECS cluster ("default"), task definition, an
# internet-facing load balancer with HTTPS and a certificate, target group, its own security
# groups and CPU autoscaling.
#   https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-work.html

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

# Used by ECS itself (not by the app) to pull the image, write logs and read the DB password.
resource "aws_iam_role" "execution" {
  name_prefix = "${var.name}-execution-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# The parameter uses the default AWS-managed key, so no KMS permission is needed.
resource "aws_iam_role_policy" "execution_db_password" {
  role = aws_iam_role.execution.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ssm:GetParameters"
      Resource = aws_ssm_parameter.db_password.arn
    }]
  })
}

# Lets ECS create and delete the load balancer, certificate and so on.
resource "aws_iam_role" "infrastructure" {
  name_prefix = "${var.name}-infrastructure-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "infrastructure" {
  role       = aws_iam_role.infrastructure.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRoleforExpressGatewayServices"
}

# Attached to the tasks next to the security groups Express Mode creates (which let the load
# balancer in), so the DB rule below applies to the tasks.
resource "aws_security_group" "app" {
  name_prefix = "${var.name}-app-"
  description = "App tasks: outbound only"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_ecs_express_gateway_service" "app" {
  service_name            = var.name
  execution_role_arn      = aws_iam_role.execution.arn
  infrastructure_role_arn = aws_iam_role.infrastructure.arn

  # Graviton (Arm): cheaper than x86. scripts/release.sh builds the image for linux/arm64.
  cpu_architecture  = "ARM64"
  cpu               = tostring(var.task_cpu)
  memory            = tostring(var.task_memory)
  health_check_path = "/health"

  # Make apply wait for the deployment, and fail if Express Mode rolls it back.
  wait_for_steady_state = true

  network_configuration {
    subnets         = module.vpc.public_subnets
    security_groups = [aws_security_group.app.id]
  }

  scaling_target {
    auto_scaling_metric = "AVERAGE_CPU"
    min_task_count      = var.min_tasks
    max_task_count      = var.max_tasks
  }

  primary_container {
    image          = "${aws_ecr_repository.app.repository_url}:${var.app_version}"
    container_port = 3000 # the app's default PORT

    aws_logs_configuration {
      log_group = aws_cloudwatch_log_group.app.name
    }

    # pg reads PGPASSWORD itself (see src/db.ts). verify-full checks the server certificate and
    # its name against the RDS CA bundle in the image.
    environment {
      name  = "DATABASE_URL"
      value = "postgres://${aws_db_instance.main.username}@${aws_db_instance.main.address}:5432/${aws_db_instance.main.db_name}?sslmode=verify-full"
    }
    secret {
      name       = "PGPASSWORD"
      value_from = aws_ssm_parameter.db_password.arn
    }
  }

  # Destroy must not remove a role's policy before ECS is done with it, or the service gets
  # stuck in DRAINING. The DB rule must exist before the first task starts, because it runs
  # migrations on startup.
  depends_on = [
    aws_iam_role_policy_attachment.execution,
    aws_iam_role_policy.execution_db_password,
    aws_iam_role_policy_attachment.infrastructure,
    aws_vpc_security_group_ingress_rule.db_from_app,
  ]
}
