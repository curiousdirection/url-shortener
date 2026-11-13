# Values printed at the end of `terraform apply`. Show them again any time with
# `terraform output` (or `terraform output -raw base_url` for just one, without quotes).

# The public HTTPS address, e.g. https://xx.ecs.eu-north-1.on.aws. Express Mode makes it up
# when it creates the service, so it is only known after the first apply.
output "base_url" {
  value = aws_ecs_express_gateway_service.app.ingress_paths[0].endpoint
}

# Where scripts/release.sh pushes the image.
output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

# The database's address and port. It is only reachable from inside the VPC.
output "rds_endpoint" {
  value = aws_db_instance.main.endpoint
}
