# The CloudFront distribution in front of the function. Why: docs/decisions/0007-cdn-cloudfront.md.
# The public address is its *.cloudfront.net name (no custom domain).

locals {
  # AWS managed policies, by their fixed IDs:
  #   https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-cache-policies.html
  #   https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-origin-request-policies.html
  # Only managed policies, because CI can't create policies.
  #
  # CachingOptimized: the cache key is the path alone (no query strings or cookies, and no
  # headers except a normalized Accept-Encoding), and the TTL follows the origin's Cache-Control
  # between 1 second and 1 year. The app's max-age=86400 on a redirect and max-age=10 on a 404
  # therefore apply as sent. A 404 is also an error response, which CloudFront caches for the
  # longer of the origin's max-age and its 10-second default, so 10 seconds holds either way.
  # It sets a minimum TTL above 0, so CloudFront caches even a response marked no-store: that is
  # why /health has its own behaviour below.
  cache_policy_caching_optimized = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  cache_policy_caching_disabled  = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  # AllViewerExceptHostHeader: forwards everything the viewer sent except Host. CloudFront then
  # sets Host to the function URL's, which the function URL needs. The default and /health
  # behaviours have no origin request policy, and CloudFront sets that Host for them too.
  origin_request_policy_all_viewer_except_host = "b689b0a8-53d0-40ab-baf2-68738e2966ac"

  # "https://abc123.lambda-url.eu-north-1.on.aws/" without the scheme and the slash.
  function_url_host = trimsuffix(trimprefix(aws_lambda_function_url.app.function_url, "https://"), "/")
  origin_id         = "function-url"
}

# CloudFront signs every request to the function URL with this (SigV4, service "lambda").
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

    # One more cache layer between CloudFront's regional caches and the function, so each link is
    # fetched from the function about once, not once per region. Charged per request, so off for
    # practice.
    dynamic "origin_shield" {
      for_each = var.origin_shield_region == null ? [] : [var.origin_shield_region]
      content {
        enabled              = true
        origin_shield_region = origin_shield.value
      }
    }
  }

  # GET /:code, the redirect. Cached by the origin's Cache-Control (see the policy above).
  default_cache_behavior {
    target_origin_id       = local.origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = local.cache_policy_caching_optimized
  }

  # The API, never cached. https-only: a POST must not be redirected, which can drop its body.
  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = local.origin_id
    viewer_protocol_policy   = "https-only"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = local.cache_policy_caching_disabled
    origin_request_policy_id = local.origin_request_policy_all_viewer_except_host

    # The app builds shortUrl from the viewer's host (see requestOrigin in src/app.ts).
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.forwarded_host.arn
    }
  }

  # The deploy check and uptime probes: must reach the function every time. The app also sends
  # no-store, but the default behaviour's cache policy would cache it anyway.
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

  # The default *.cloudfront.net certificate: no custom domain, no ACM certificate.
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
