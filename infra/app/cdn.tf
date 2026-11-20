# CloudFront in front of the function, and of the web page's bucket (web.tf).
# Why: docs/decisions/0007-cdn-cloudfront.md and docs/decisions/0009-frontend-on-s3.md.

locals {
  function_url_host = trimsuffix(trimprefix(aws_lambda_function_url.app.function_url, "https://"), "/")
  origin_id         = "function-url"
  web_origin_id     = "web-bucket"
}

# AWS's ready-made CloudFront policies, looked up by name.
# CI isn't allowed to create its own cache or origin request policies.
#   https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-cache-policies.html

# For redirects and the web page's files: keeps each one as long as its Cache-Control says.
# It always keeps a response for at least 1 second, even one marked no-store, so /health uses the next one instead.
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

# For /api/* and /health: keeps nothing.
data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

# For /api/*: passes the visitor's headers on to the function, except Host.
# The function URL only answers requests addressed to its own name, so CloudFront puts that in instead.
data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

# For every behaviour: AWS's Managed-SecurityHeadersPolicy headers plus a Content-Security-Policy, which the managed one can't be extended with.
# The override flags match the managed policy, except that the CSP replaces any the origin sends.
resource "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "${var.name}-security-headers"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000
      override                   = false
    }
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "SAMEORIGIN"
      override     = false
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = false
    }
    xss_protection {
      protection = true
      mode_block = true
      override   = false
    }
    content_security_policy {
      content_security_policy = "default-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'; object-src 'none'"
      override                = true
    }
  }
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

  # What / shows.
  # CloudFront turns / into /index.html before it picks a behaviour, so / gets the /index.html behaviour below.
  default_root_object = "index.html"

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

    # An extra cache layer, so each link reaches the function about once.
    # Off for practice.
    dynamic "origin_shield" {
      for_each = var.origin_shield_region == null ? [] : [var.origin_shield_region]
      content {
        enabled              = true
        origin_shield_region = origin_shield.value
      }
    }
  }

  # The web page's bucket.
  # Signed with its own origin access control, which is why it has no origin config.
  origin {
    origin_id                = local.web_origin_id
    domain_name              = aws_s3_bucket.web.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.web.id
  }

  # Redirects, cached as the app's Cache-Control says.
  default_cache_behavior {
    target_origin_id           = local.origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers.id
  }

  # The API, never cached.
  # https-only, because a redirected POST can lose its body.
  ordered_cache_behavior {
    path_pattern               = "/api/*"
    target_origin_id           = local.origin_id
    viewer_protocol_policy     = "https-only"
    allowed_methods            = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods             = ["GET", "HEAD"]
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_disabled.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id

    # For shortUrl (src/app.ts).
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.forwarded_host.arn
    }
  }

  # Never cached, so health checks reach the function.
  ordered_cache_behavior {
    path_pattern               = "/health"
    target_origin_id           = local.origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_disabled.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers.id
  }

  # The web page, cached as the Cache-Control set on each file at upload says (infra/scripts/release-web.sh).
  ordered_cache_behavior {
    path_pattern               = "/index.html"
    target_origin_id           = local.web_origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers.id
  }

  ordered_cache_behavior {
    path_pattern               = "/assets/*"
    target_origin_id           = local.web_origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers.id
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
