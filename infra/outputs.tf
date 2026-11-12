# Values printed at the end of `terraform apply`. Show them again any time with
# `terraform output` (or `terraform output -raw base_url` for just one, without quotes).

# The database's address and port. It is only reachable from inside the VPC.
output "rds_endpoint" {
  value = aws_db_instance.main.endpoint
}
