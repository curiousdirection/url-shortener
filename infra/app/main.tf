# The app: one Lambda function (a zip of the bundled code), its function URL and its log group.
#
# The table and the function's role come from the foundation stack (see the data source below).

# What the foundation stack created, read from its state in S3. If this fails with "no
# outputs", the foundation stack has not been applied yet: do that first (see "Set up and first
# run" in ../README.md).
#
# The bucket is the one this stack's own state is in. It is passed in (state_bucket), not worked
# out here, so there is one place that says which bucket it is (the TF_STATE_BUCKET variable in
# CI, backend.hcl and terraform.tfvars on your machine; see ../README.md).
data "terraform_remote_state" "foundation" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "foundation/terraform.tfstate"
    region = var.region
  }
}

locals {
  foundation = data.terraform_remote_state.foundation.outputs
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.name}/app"
  retention_in_days = 7
}

resource "aws_lambda_function" "app" {
  function_name = var.name
  description   = "Release ${var.app_version}"
  role          = local.foundation.lambda_role_arn

  # Handler "index.handler" is `handler` exported from index.mjs, which infra/scripts/build-zip.sh
  # builds from src/lambda.ts. The runtime is the newest Node.js one that is generally
  # available; .node-version matches it (see ADR 0006).
  runtime       = "nodejs24.x"
  handler       = "index.handler"
  architectures = ["arm64"] # Graviton: cheaper than x86
  memory_size   = var.memory_size
  timeout       = 10

  # build-zip.sh puts the zip here and prints its hash. Terraform is given the hash instead of
  # reading the file, so a plan without the zip (CI's plan job) can reuse the current hash and
  # show only real changes.
  filename         = "${path.module}/../../build/app.zip"
  source_code_hash = var.package_hash

  environment {
    variables = {
      TABLE_NAME = local.foundation.table_name
    }
  }

  # By default Lambda writes START, END and REPORT lines for every request. At full scale that is
  # terabytes a month in CloudWatch (thousands of dollars), so only warnings and errors are kept.
  # Log levels need the JSON format.
  #   https://aws.amazon.com/blogs/compute/introducing-advanced-logging-controls-for-aws-lambda-functions/
  logging_config {
    log_format       = "JSON"
    system_log_level = "WARN"
    log_group        = aws_cloudwatch_log_group.app.name
  }
}

# The public HTTPS address. Auth type NONE means anyone can call it; the CDN PR will switch it to
# AWS_IAM, so that only the CDN can (see docs/security.md).
resource "aws_lambda_function_url" "app" {
  function_name      = aws_lambda_function.app.function_name
  authorization_type = "NONE"
}

# With auth type NONE, the function's resource policy must still allow the call. Two statements
# are needed since October 2025: one for the URL, one for the invoke through it.
#   https://docs.aws.amazon.com/lambda/latest/dg/urls-auth.html
resource "aws_lambda_permission" "url" {
  statement_id           = "FunctionURLAllowPublicAccess"
  function_name          = aws_lambda_function.app.function_name
  action                 = "lambda:InvokeFunctionUrl"
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "invoke" {
  statement_id             = "FunctionURLInvokeAllowPublicAccess"
  function_name            = aws_lambda_function.app.function_name
  action                   = "lambda:InvokeFunction"
  principal                = "*"
  invoked_via_function_url = true
}
