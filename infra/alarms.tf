# Alarms that email you when the site fails or the database fills up. Set alarm_email in
# terraform.tfvars; AWS then emails a link you must click once before alerts arrive.

resource "aws_sns_topic" "alarms" {
  name = "${var.name}-alarms"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email == null ? 0 : 1
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# Express Mode creates the load balancer, so find it through the service's target group.
data "aws_ecs_cluster" "default" {
  cluster_name = "default"
  depends_on   = [aws_ecs_express_gateway_service.app]
}

data "aws_ecs_service" "app" {
  cluster_arn  = data.aws_ecs_cluster.default.arn
  service_name = aws_ecs_express_gateway_service.app.service_name
}

data "aws_lb_target_group" "app" {
  arn = one(data.aws_ecs_service.app.load_balancer[*].target_group_arn)
}

data "aws_lb" "app" {
  arn = one(data.aws_lb_target_group.app.load_balancer_arns)
}

locals {
  alarm_actions = [aws_sns_topic.alarms.arn]
}

# The app answers more than 5% of requests with a 5xx, two 5-minute periods in a row.
resource "aws_cloudwatch_metric_alarm" "app_5xx" {
  alarm_name          = "${var.name}-app-5xx"
  alarm_description   = "More than 5% of requests get a server error from the app."
  comparison_operator = "GreaterThanThreshold"
  threshold           = 5
  evaluation_periods  = 2
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  metric_query {
    id          = "rate"
    expression  = "IF(requests > 0, 100 * errors / requests, 0)"
    return_data = true
  }
  metric_query {
    id = "errors"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      stat        = "Sum"
      period      = 300
      dimensions  = { LoadBalancer = data.aws_lb.app.arn_suffix }
    }
  }
  metric_query {
    id = "requests"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      stat        = "Sum"
      period      = 300
      dimensions  = { LoadBalancer = data.aws_lb.app.arn_suffix }
    }
  }
}

# The load balancer itself answers 5xx: usually no healthy task (503) or a task that died
# mid-request (502).
resource "aws_cloudwatch_metric_alarm" "lb_5xx" {
  alarm_name          = "${var.name}-load-balancer-5xx"
  alarm_description   = "The load balancer can't reach a healthy task."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  dimensions          = { LoadBalancer = data.aws_lb.app.arn_suffix }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 5
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# Less than 10% of the database's disk is free.
resource "aws_cloudwatch_metric_alarm" "db_storage" {
  alarm_name          = "${var.name}-db-storage"
  alarm_description   = "The database has less than 10% of its disk free."
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.main.identifier }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "LessThanThreshold"
  threshold           = var.db_allocated_storage * 0.1 * 1024 * 1024 * 1024
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}
