# CloudWatch alarms on the function and the table, sent by email through one SNS topic.
# They are in this stack, not infra/app, because CI's deploy role can't create resources (infra/bootstrap/deploy-role.tf).
# There are none on CloudFront: its metrics are in us-east-1, where the project account may only read CloudWatch.

locals {
  # Five-minute periods; an alarm fires when 2 of the last 3 breach, so one bad period doesn't page anyone.
  alarm_period          = 300
  alarm_periods         = 3
  alarm_breaching       = 2
  alarm_actions         = [aws_sns_topic.alarms.arn]
  error_min_count       = 5
  error_rate_percentage = 5

  # The function is made by infra/app with function_name = var.name, after this stack, so it is named here, not read from that state.
  function_name = var.name
}

# Not encrypted with KMS: CloudWatch can't publish to a topic that uses the AWS managed SNS key, and alarm messages hold no secrets.
resource "aws_sns_topic" "alarms" {
  name = "${var.name}-alarms"
}

# AWS emails a link to confirm this; see "Set up and first run" in infra/README.md.
resource "aws_sns_topic_subscription" "alarm_email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# Fires on a rate, with a minimum count so that 1 failure out of 2 requests at practice traffic doesn't page anyone.
# Errors counts invocations that throw, time out or run out of memory.
# Hono answers an exception in a route with a 500 response, which Lambda counts as a success, so this alarm doesn't see those.
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.name}-lambda-errors"
  alarm_description   = "The function failed at least ${local.error_min_count} invocations and more than ${local.error_rate_percentage}% of them in a 5-minute period, in 2 of the last 3 periods."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  evaluation_periods  = local.alarm_periods
  datapoints_to_alarm = local.alarm_breaching
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  # 1 when both conditions hold, else 0.
  metric_query {
    id          = "breaching"
    expression  = "(errors >= ${local.error_min_count}) AND (errors / invocations * 100 > ${local.error_rate_percentage})"
    label       = "Error count and rate both over the limit"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      namespace   = "AWS/Lambda"
      metric_name = "Errors"
      dimensions  = { FunctionName = local.function_name }
      stat        = "Sum"
      period      = local.alarm_period
    }
  }

  metric_query {
    id = "invocations"
    metric {
      namespace   = "AWS/Lambda"
      metric_name = "Invocations"
      dimensions  = { FunctionName = local.function_name }
      stat        = "Sum"
      period      = local.alarm_period
    }
  }
}

# Any throttle means a request was refused for lack of concurrency, so one period is enough.
resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name          = "${var.name}-lambda-throttles"
  alarm_description   = "Lambda refused requests to the function because it hit its concurrency limit."
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  dimensions          = { FunctionName = local.function_name }
  statistic           = "Sum"
  period              = local.alarm_period
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# The same rule as the function's errors alarm, on HTTP 500s from DynamoDB.
# DynamoDB publishes SystemErrors only per operation, never per table alone, so the alarm adds up the two operations the function calls (GetItem and PutItem, the only ones iam.tf allows).
# The request count is the successful requests (the SampleCount of SuccessfulRequestLatency) plus the errors.
# DynamoDB only publishes a data point when there is something to count, so FILL turns a missing one into 0; without it the sum is missing whenever one operation had none.
resource "aws_cloudwatch_metric_alarm" "table_system_errors" {
  alarm_name          = "${var.name}-table-system-errors"
  alarm_description   = "DynamoDB answered at least ${local.error_min_count} requests to ${aws_dynamodb_table.urls.name} and more than ${local.error_rate_percentage}% of them with a 500 in a 5-minute period, in 2 of the last 3 periods."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  evaluation_periods  = local.alarm_periods
  datapoints_to_alarm = local.alarm_breaching
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  metric_query {
    id          = "breaching"
    expression  = "(errors >= ${local.error_min_count}) AND (errors / (errors + ok) * 100 > ${local.error_rate_percentage})"
    label       = "Error count and rate both over the limit"
    return_data = true
  }

  metric_query {
    id         = "errors"
    expression = "FILL(get_errors, 0) + FILL(put_errors, 0)"
  }

  metric_query {
    id         = "ok"
    expression = "FILL(get_ok, 0) + FILL(put_ok, 0)"
  }

  metric_query {
    id = "get_errors"
    metric {
      namespace   = "AWS/DynamoDB"
      metric_name = "SystemErrors"
      dimensions  = { TableName = aws_dynamodb_table.urls.name, Operation = "GetItem" }
      stat        = "Sum"
      period      = local.alarm_period
    }
  }

  metric_query {
    id = "put_errors"
    metric {
      namespace   = "AWS/DynamoDB"
      metric_name = "SystemErrors"
      dimensions  = { TableName = aws_dynamodb_table.urls.name, Operation = "PutItem" }
      stat        = "Sum"
      period      = local.alarm_period
    }
  }

  metric_query {
    id = "get_ok"
    metric {
      namespace   = "AWS/DynamoDB"
      metric_name = "SuccessfulRequestLatency"
      dimensions  = { TableName = aws_dynamodb_table.urls.name, Operation = "GetItem" }
      stat        = "SampleCount"
      period      = local.alarm_period
    }
  }

  metric_query {
    id = "put_ok"
    metric {
      namespace   = "AWS/DynamoDB"
      metric_name = "SuccessfulRequestLatency"
      dimensions  = { TableName = aws_dynamodb_table.urls.name, Operation = "PutItem" }
      stat        = "SampleCount"
      period      = local.alarm_period
    }
  }
}

# ReadThrottleEvents and WriteThrottleEvents are published per table and count every cause of throttling, including the on-demand limits.
# The SDK retries a throttled request, so unlike the function's throttles alarm this one waits for more than one period.
# FILL as in table_system_errors: a period with only read throttles would otherwise have no sum.
resource "aws_cloudwatch_metric_alarm" "table_throttles" {
  alarm_name          = "${var.name}-table-throttles"
  alarm_description   = "DynamoDB throttled reads or writes to ${aws_dynamodb_table.urls.name} in 2 of the last 3 5-minute periods."
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = local.alarm_periods
  datapoints_to_alarm = local.alarm_breaching
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  metric_query {
    id          = "throttles"
    expression  = "FILL(reads, 0) + FILL(writes, 0)"
    label       = "Throttled reads and writes"
    return_data = true
  }

  metric_query {
    id = "reads"
    metric {
      namespace   = "AWS/DynamoDB"
      metric_name = "ReadThrottleEvents"
      dimensions  = { TableName = aws_dynamodb_table.urls.name }
      stat        = "Sum"
      period      = local.alarm_period
    }
  }

  metric_query {
    id = "writes"
    metric {
      namespace   = "AWS/DynamoDB"
      metric_name = "WriteThrottleEvents"
      dimensions  = { TableName = aws_dynamodb_table.urls.name }
      stat        = "Sum"
      period      = local.alarm_period
    }
  }
}
