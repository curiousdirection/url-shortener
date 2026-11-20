# CloudFront's access logs, only when cdn_access_logs is true.
# One JSON line per request in CloudWatch Logs.
# How to read them: "Access logs" under "Deploy" in infra/README.md.
#   https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/standard-logging.html

# CloudFront's log delivery is set up in us-east-1, so the log group is there too.

data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_group" "access" {
  #checkov:skip=CKV_AWS_158: The log holds no secrets, and the AWS-owned key costs nothing.
  #checkov:skip=CKV_AWS_338: Deleted after 7 days on purpose (docs/security.md).
  count    = var.cdn_access_logs ? 1 : 0
  provider = aws.us_east_1
  # Letters, digits, - and _ only: the log delivery refuses other characters, so no slashes as in /url-shortener/app.
  name              = "${var.name}-cdn-access"
  retention_in_days = 7
}

# Lets the log delivery service write to the group, and only for this account.
resource "aws_cloudwatch_log_resource_policy" "access" {
  count       = var.cdn_access_logs ? 1 : 0
  provider    = aws.us_east_1
  policy_name = "${var.name}-cdn-access"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "delivery.logs.amazonaws.com" }
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource  = "${aws_cloudwatch_log_group.access[0].arn}:log-stream:*"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:*" }
      }
    }]
  })
}

resource "aws_cloudwatch_log_delivery_source" "access" {
  count        = var.cdn_access_logs ? 1 : 0
  provider     = aws.us_east_1
  name         = "${var.name}-cdn"
  log_type     = "ACCESS_LOGS"
  resource_arn = aws_cloudfront_distribution.app.arn
}

# The format can't be changed later; a new one means a new destination.
resource "aws_cloudwatch_log_delivery_destination" "access" {
  count         = var.cdn_access_logs ? 1 : 0
  provider      = aws.us_east_1
  name          = "${var.name}-cdn-access"
  output_format = "json"

  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.access[0].arn
  }
}

resource "aws_cloudwatch_log_delivery" "access" {
  count                    = var.cdn_access_logs ? 1 : 0
  provider                 = aws.us_east_1
  delivery_source_name     = aws_cloudwatch_log_delivery_source.access[0].name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.access[0].arn

  # Only these fields: nothing that identifies a visitor (docs/security.md).
  # Times are in seconds.
  record_fields = [
    "timestamp(ms)",
    "x-edge-request-id", # the x-amz-cf-id response header, to find one request
    "x-edge-location",
    "cs-method",
    "cs-uri-stem", # the path: a short code, /api/... or /health
    "sc-status",
    "x-edge-detailed-result-type", # Hit, Miss, or which error
    "time-to-first-byte",          # from the request reaching the edge to the first byte sent back
    "time-taken",                  # the same, to the last byte
    "origin-fbl",                  # how long the function URL took to send its first byte
  ]

  depends_on = [aws_cloudwatch_log_resource_policy.access]
}
