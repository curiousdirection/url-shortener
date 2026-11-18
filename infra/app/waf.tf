# Rate limiting by client IP. Why: docs/decisions/0007-cdn-cloudfront.md. Only made when
# rate_limiting is true (full scale): WAF bills about $7 a month even when idle.

# A web ACL for CloudFront must be in us-east-1, whatever region the rest of the stack uses.
# That region is allowed on this account (docs/security.md).
resource "aws_wafv2_web_acl" "app" {
  count       = var.rate_limiting ? 1 : 0
  provider    = aws.us_east_1
  name        = var.name
  description = "Rate limits for the ${var.name} distribution"
  scope       = "CLOUDFRONT"

  # Anything no rule blocks is allowed.
  default_action {
    allow {}
  }

  custom_response_body {
    key          = "rate-limited"
    content      = "{\"error\":\"too many requests\"}"
    content_type = "APPLICATION_JSON"
  }

  # Every request. Requests that CloudFront answers from its cache are counted too.
  rule {
    name     = "rate-limit-all"
    priority = 1

    action {
      block {
        custom_response {
          response_code            = 429
          custom_response_body_key = "rate-limited"
        }
      }
    }

    statement {
      rate_based_statement {
        limit                 = var.rate_limit_all
        evaluation_window_sec = 300
        aggregate_key_type    = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-rate-limit-all"
      sampled_requests_enabled   = true
    }
  }

  # Creating links: a POST to /api/*.
  rule {
    name     = "rate-limit-create"
    priority = 2

    action {
      block {
        custom_response {
          response_code            = 429
          custom_response_body_key = "rate-limited"
        }
      }
    }

    statement {
      rate_based_statement {
        limit                 = var.rate_limit_create
        evaluation_window_sec = 300
        aggregate_key_type    = "IP"

        scope_down_statement {
          and_statement {
            statement {
              byte_match_statement {
                search_string         = "POST"
                positional_constraint = "EXACTLY"
                field_to_match {
                  method {}
                }
                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
            statement {
              byte_match_statement {
                search_string         = "/api/"
                positional_constraint = "STARTS_WITH"
                field_to_match {
                  uri_path {}
                }
                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-rate-limit-create"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = var.name
    sampled_requests_enabled   = true
  }
}
