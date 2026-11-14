# The two IAM roles that ECS uses for the app. They live here, not in the app stack, so the
# role that deploys the app (see ../bootstrap) never needs permission to create or change
# roles. It only needs permission to hand these two to ECS ("iam:PassRole").
#
# The names are fixed (not `name_prefix`) so that the deploy role's PassRole rule can name
# them exactly.

# Used by ECS itself (not by the app) to pull the image, write logs and read the DB password.
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
