# Values printed at the end of `terraform apply`. Show them again any time with
# `terraform output` (or `terraform output -raw url` for just one, without quotes).

# The public HTTPS address, e.g. https://abc123.lambda-url.eu-north-1.on.aws. Lambda makes up
# the id when it creates the URL, so it is only known after the first apply. The trailing slash
# is dropped, so "$url/health" works.
output "url" {
  value = trimsuffix(aws_lambda_function_url.app.function_url, "/")
}

# The release that is deployed now. The deploy workflow compares it with the new commit to
# decide whether anything changed.
output "app_version" {
  value = var.app_version
}

# The hash of the zip that is deployed now. CI's plan reuses it, so that the plan only shows
# real changes to the infrastructure and not new code.
output "package_hash" {
  value = var.package_hash
}
