# Values printed at the end of `terraform apply`. Show them again any time with
# `terraform output` (or `terraform output -raw url` for just one, without quotes).

# The public HTTPS address, e.g. https://xx.ecs.eu-north-1.on.aws. Express Mode makes it up
# when it creates the service, so it is only known after the first apply.
output "url" {
  value = aws_ecs_express_gateway_service.app.ingress_paths[0].endpoint
}

# Where scripts/release.sh pushes the image.
output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

# The database's writer address. It is only reachable from inside the VPC.
output "rds_endpoint" {
  value = aws_rds_cluster.main.endpoint
}

# What the RDS Data API needs to run SQL (see "Look at the data" in README.md).
output "db_cluster_arn" {
  value = aws_rds_cluster.main.arn
}

output "db_secret_arn" {
  value = aws_secretsmanager_secret.db.arn
}
