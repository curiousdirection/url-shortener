# Values printed at the end of `terraform apply`.
# Show them again any time with `terraform output`, or with `terraform output -raw url` for just one, without quotes.

# The public address, e.g. https://d111111abcdef8.cloudfront.net (no trailing slash).
output "url" {
  value = "https://${aws_cloudfront_distribution.app.domain_name}"
}

# For cache invalidations ("Take down a link" in infra/README.md).
output "distribution_id" {
  value = aws_cloudfront_distribution.app.id
}

# The bucket the web page is uploaded to (infra/scripts/release-web.sh).
output "web_bucket" {
  value = aws_s3_bucket.web.bucket
}

# The function's own address.
# Only CloudFront can call it; use `url`.
output "function_url" {
  value = trimsuffix(aws_lambda_function_url.app.function_url, "/")
}

# The release that is deployed now.
# CI's deploy job compares it with the new commit to decide whether anything changed.
output "app_version" {
  value = var.app_version
}

# The hash of the zip that is deployed now.
# CI's plan reuses it, so that the plan only shows real changes to the infrastructure and not new code.
output "package_hash" {
  value = var.package_hash
}
