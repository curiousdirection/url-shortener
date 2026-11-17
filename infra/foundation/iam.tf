# The IAM roles ECS uses for the app and for the one-off database setup. They're here, not in
# the app stack, so the CI deploy role never has to create or change roles. It only passes the
# app's roles to ECS, never the setup role.
#
# The names are fixed (not `name_prefix`) so that the deploy role's PassRole rule can name
# them exactly.

data "aws_caller_identity" "current" {}

# Used by ECS itself (not by the app) to pull the image and write logs.
resource "aws_iam_role" "execution" {
  name = "${var.name}-execution"
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

# Used by the app's own code. Its only permission is to log in to the database as `app`, which
# src/db.ts does with a token signed by this role.
resource "aws_iam_role" "task" {
  name = "${var.name}-task"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
      # Only tasks of this account can use the role.
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })
}

# The ARN names one database account on one database instance (the instance's resource id,
# not its name). Nothing else is allowed.
#   https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.IAMPolicy.html
resource "aws_iam_role_policy" "task_db_connect" {
  role = aws_iam_role.task.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "rds-db:connect"
      Resource = "arn:aws:rds-db:${var.region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_db_instance.main.resource_id}/app"
    }]
  })
}

# The execution role of the setup task, the only reader of the database password. It is
# separate from the app's, and the deploy role can't pass it (bootstrap/deploy-role.tf).
resource "aws_iam_role" "db_setup_execution" {
  name = "${var.name}-db-setup-execution"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "db_setup_execution" {
  role       = aws_iam_role.db_setup_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# The parameter uses the default AWS-managed key, so no KMS permission is needed.
resource "aws_iam_role_policy" "db_setup_execution_db_password" {
  role = aws_iam_role.db_setup_execution.name
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
  name = "${var.name}-infrastructure"
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
