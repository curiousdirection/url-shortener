# Values printed at the end of `terraform apply`. Show them again any time with
# `terraform output` (or `terraform output -raw base_url` for just one, without quotes).

# The load balancer's address, e.g. url-shortener-123.elb.eu-north-1.amazonaws.com.
output "nlb_dns_name" {
  value = module.nlb.dns_name
}

output "base_url" {
  description = "Public URL (also what the app uses to build shortUrl)."
  value       = local.base_url
}

# The database's address and port. It is only reachable from inside the VPC.
output "rds_endpoint" {
  value = module.db.db_instance_endpoint
}

# Where scripts/release.sh uploads the app. It reads this value to find the bucket.
output "release_bucket" {
  value = aws_s3_bucket.releases.id
}
