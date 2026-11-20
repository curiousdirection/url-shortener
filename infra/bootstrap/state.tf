# The S3 bucket that holds the Terraform state of all three stacks, one file each (bootstrap/, foundation/ and app/terraform.tfstate).
# Whoever can write the state can change what Terraform builds, so it is locked down.

data "aws_caller_identity" "current" {}

locals {
  # Bucket names are global across all AWS accounts, so the account id makes it unique.
  # The name is handed on through `output state_bucket`: to backend.hcl, to the `state_bucket` variable of the app stack and to the TF_STATE_BUCKET variable in GitHub.
  # Nothing else rebuilds it.
  state_bucket = "${var.name}-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "state" {
  bucket = local.state_bucket
  # Without this, AWS refuses to delete a bucket that still holds state or old versions.
  # `terraform destroy` here fails on purpose until you have emptied it.
  force_destroy = false
}

# Keep every old version of each state file, so a bad write can be undone.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt at rest with the S3-managed key (SSE-S3).
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Never public, whatever anyone does to a policy or an ACL later.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Old versions are only for undoing mistakes, so drop them after 90 days.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Versioning must be switched on first.
  depends_on = [aws_s3_bucket_versioning.state]
}

# Refuse any request that doesn't use HTTPS.
resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })

  # The public access block and the policy are both "bucket settings"; applying them at the same time can fail with a conflict.
  depends_on = [aws_s3_bucket_public_access_block.state]
}
