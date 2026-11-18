# CloudFront in front of the function. Why: docs/decisions/0007-cdn-cloudfront.md.

locals {
  # CloudFront's cache rules. These are AWS's ready-made ones, by their fixed IDs, because CI
  # isn't allowed to create its own:
  #   https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-cache-policies.html
  # caching_optimized (redirects): keeps each path as long as the app's Cache-Control says, but
  # always at least 1 second, even with no-store. That's why /health uses caching_disabled.
  # caching_disabled (/api/* and /health): never caches.
  cache_policy_caching_optimized = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  cache_policy_caching_disabled  = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  # Forwards everything but Host: the function URL needs its own.
  origin_request_policy_all_viewer_except_host = "b689b0a8-53d0-40ab-baf2-68738e2966ac"

  function_url_host = trimsuffix(trimprefix(aws_lambda_function_url.app.function_url, "https://"), "/")
  origin_id         = "function-url"
}

# Signs every request to the function URL, so only CloudFront can call it.
resource "aws_cloudfront_origin_access_control" "app" {
  name                              = var.name
  description                       = "Signs requests to the ${var.name} function URL"
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "forwarded_host" {
  name    = "${var.name}-forwarded-host"
  comment = "Copies the viewer's Host into X-Forwarded-Host"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = file("${path.module}/functions/forwarded-host.js")
}

resource "aws_cloudfront_distribution" "app" {
  comment         = var.name
  enabled         = true
  is_ipv6_enabled = true
  http_version    = "http2and3"
  web_acl_id      = var.rate_limiting ? aws_wafv2_web_acl.app[0].arn : null

  origin {
    origin_id                = local.origin_id
    domain_name              = local.function_url_host
    origin_access_control_id = aws_cloudfront_origin_access_control.app.id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # An extra cache layer, so each link reaches the function about once. Off for practice.
    dynamic "origin_shield" {
      for_each = var.origin_shield_region == null ? [] : [var.origin_shield_region]
      content {
        enabled              = true
        origin_shield_region = origin_shield.value
      }
    }
  }

  # Redirects, cached as the app's Cache-Control says.
  default_cache_behavior {
    target_origin_id       = local.origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = local.cache_policy_caching_optimized
  }

  # The API, never cached. https-only, because a redirected POST can lose its body.
  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = local.origin_id
    viewer_protocol_policy   = "https-only"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = local.cache_policy_caching_disabled
    origin_request_policy_id = local.origin_request_policy_all_viewer_except_host

    # For shortUrl (src/app.ts).
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.forwarded_host.arn
    }
  }

  # Never cached, so health checks reach the function.
  ordered_cache_behavior {
    path_pattern           = "/health"
    target_origin_id       = local.origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = local.cache_policy_caching_disabled
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
