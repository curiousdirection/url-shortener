# The role the Lambda function runs as. It is here, not in the app stack, so the CI deploy role
# never has to create or change roles. It only passes this one to Lambda.
#
# The name is fixed (not `name_prefix`) so that the deploy role's PassRole rule can name it
# exactly.

resource "aws_iam_role" "lambda" {
  name = "${var.name}-lambda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# All the function may do: read and write items in the one table, and write its own logs. The
# log group is made by the app stack; it is named here because the foundation is applied first.
resource "aws_iam_role_policy" "lambda" {
  role = aws_iam_role.lambda.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem"]
        Resource = aws_dynamodb_table.urls.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/${var.name}/app:*"
      },
    ]
  })
}

data "aws_caller_identity" "current" {}
