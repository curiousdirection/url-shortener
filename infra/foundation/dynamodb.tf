# The table that holds the links.
# One item per short code.
# Why DynamoDB:
# docs/decisions/0006-move-to-lambda-and-dynamodb.md

resource "aws_dynamodb_table" "urls" {
  name = "${var.name}-urls"

  # On-demand: pay per request, nothing to size, and it follows
  # spikes.
  billing_mode = "PAY_PER_REQUEST"

  # Only the key is declared. long_url is just another attribute
  # on the item.
  hash_key = "code"
  attribute {
    name = "code"
    type = "S"
  }

  # Encrypted at rest.
  # DynamoDB always does this; with no server_side_encryption
  # block it uses an AWS-owned key, which costs nothing and
  # leaves no KMS key to manage.

  # Lets you restore the table to any second in the last 35 days.
  # Off for practice, on for full scale.
  point_in_time_recovery {
    enabled = var.table_point_in_time_recovery
  }

  # When true, AWS refuses to delete the table (even `terraform
  # destroy`) until you turn it off.
  deletion_protection_enabled = var.table_deletion_protection
}
