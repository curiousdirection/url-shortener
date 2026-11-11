output "nlb_dns_name" {
  value = aws_lb.main.dns_name
}

output "base_url" {
  description = "Public URL (also what the app uses to build shortUrl)."
  value       = local.base_url
}

output "rds_endpoint" {
  value = aws_db_instance.main.endpoint
}

output "release_bucket" {
  value = aws_s3_bucket.releases.id
}
