# Values printed at the end of `terraform apply`. Show them again any time with
# `terraform output` (or `terraform output -raw url` for just one, without quotes).

# The public HTTPS address, e.g. https://xx.ecs.eu-north-1.on.aws. Express Mode makes it up
# when it creates the service, so it is only known after the first apply.
output "url" {
  value = aws_ecs_express_gateway_service.app.ingress_paths[0].endpoint
}

# Where scripts/release.sh and the deploy workflow push the image.
output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

# The image tag that is deployed now. The pull request plan reuses it, so that the plan only
# shows real changes to the infrastructure and not a new image.
output "app_version" {
  value = var.app_version
}
