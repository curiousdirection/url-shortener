# A CloudTrail trail of the account's management events, kept in a private bucket, and an emailed alarm on root use or a stopped trail.

locals {
  trail_name   = "${var.name}-trail"
  trail_bucket = "${var.name}-cloudtrail-${data.aws_caller_identity.current.account_id}"
  trail_arn    = "arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.current.account_id}:trail/${local.trail_name}"
}

resource "aws_s3_bucket" "trail" {
  bucket = local.trail_bucket
  # The logs expire anyway, so a destroy may delete what is left.
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "trail" {
  bucket                  = aws_s3_bucket.trail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    id     = "expire-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = 90
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "CloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.trail.arn
        Condition = { StringEquals = { "aws:SourceArn" = local.trail_arn } }
      },
      {
        Sid       = "CloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.trail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = local.trail_arn
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.trail.arn, "${aws_s3_bucket.trail.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.trail]
}

# Only the alarm reads this copy of the events; the bucket is the record.
resource "aws_cloudwatch_log_group" "trail" {
  name              = "/${var.name}/cloudtrail"
  retention_in_days = 7
}

resource "aws_iam_role" "trail_logs" {
  name = "${var.name}-cloudtrail-logs"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          "aws:SourceArn"     = local.trail_arn
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "trail_logs" {
  role = aws_iam_role.trail_logs.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.trail.arn}:*"
    }]
  })
}

# Multi-Region so that IAM, STS and root sign-ins, which AWS records in us-east-1, are included.
# The first copy of management events is free.
resource "aws_cloudtrail" "main" {
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.trail.id
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.trail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.trail_logs.arn

  depends_on = [aws_s3_bucket_policy.trail, aws_iam_role_policy.trail_logs]
}

# Any use of the root user (the CIS benchmark's pattern) and anything that stops or deletes the trail.
resource "aws_cloudwatch_log_metric_filter" "account_security" {
  name           = "${var.name}-account-security"
  log_group_name = aws_cloudwatch_log_group.trail.name
  pattern        = "{ ($.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\") || $.eventName = \"StopLogging\" || $.eventName = \"DeleteTrail\" }"

  metric_transformation {
    name      = "AccountSecurityEvents"
    namespace = var.name
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "account_security" {
  alarm_name          = "${var.name}-account-security"
  alarm_description   = "The root user was used, or the CloudTrail trail was stopped or deleted."
  namespace           = var.name
  metric_name         = "AccountSecurityEvents"
  statistic           = "Sum"
  period              = local.alarm_period
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  depends_on = [aws_cloudwatch_log_metric_filter.account_security]
}
