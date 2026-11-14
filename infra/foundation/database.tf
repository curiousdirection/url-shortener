# The Postgres database (Amazon RDS), its firewall and its password.

# A security group is a firewall attached to a resource. This one is for the database. The only
# rule that lets anything in is db_from_app in security.tf.
resource "aws_security_group" "db" {
  # AWS requires unique names; `name_prefix` lets AWS add a random suffix.
  name_prefix = "${var.name}-db-"
  description = "Postgres from the app tasks only"
  vpc_id      = module.vpc.vpc_id

  # When this must be replaced, create the new one first, then delete the old one.
  # Otherwise the delete fails because the database is still using it.
  lifecycle {
    create_before_destroy = true
  }
}

# The database password. It is generated here, on every run, and handed straight to AWS. It
# is "ephemeral": Terraform keeps it in memory only, so it is never written to the plan, the
# state (in S3) or the logs. Alphanumeric only, so it never needs escaping.
#   https://developer.hashicorp.com/terraform/language/block/ephemeral
ephemeral "random_password" "db" {
  length  = 32
  special = false
}

# Stores the password in AWS Systems Manager Parameter Store. "SecureString" means it is
# encrypted. ECS reads it when it starts a task and passes it in as PGPASSWORD; the task
# execution role may read this one parameter and nothing else. (An RDS-managed password
# would rotate every 7 days, and running tasks would keep the old one.)
#
# `value_wo` is a write-only argument: sent to AWS, never stored in the state. Terraform
# can't see whether it changed, so it only sends it again when `value_wo_version` changes.
resource "aws_ssm_parameter" "db_password" {
  name             = "/${var.name}/db_password"
  type             = "SecureString"
  value_wo         = ephemeral.random_password.db.result
  value_wo_version = var.db_password_version

  # If the database is ever replaced, it is created with a fresh password. Replace this
  # parameter too, so that it holds the same one. (resource_id changes with a new database.)
  lifecycle {
    replace_triggered_by = [aws_db_instance.main.resource_id]
  }
}

# A random suffix for the final snapshot's name. Snapshot names must be unique, so a fixed
# name would make a second destroy fail while the first snapshot still exists. A new suffix
# is generated each time the stack is created.
resource "random_id" "final_snapshot" {
  byte_length = 4
}

# The database server itself.
resource "aws_db_instance" "main" {
  identifier = var.name
  engine     = "postgres"
  # "16" means the latest 16.x minor version.
  engine_version = "16"
  # The machine size, e.g. db.t4g.micro (see variables.tf).
  instance_class = var.db_instance_class

  db_name  = "urlshortener"
  username = "urlshortener"
  # The same write-only password as above. It is sent when the database is created, and again
  # when password_wo_version changes (which also changes the parameter, so they stay equal).
  password_wo         = ephemeral.random_password.db.result
  password_wo_version = var.db_password_version

  # Disk size in GiB. gp3 is general-purpose SSD storage. Encrypted at rest.
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  # Place it in the database subnets (and subnet group) created by the VPC module, behind the
  # database firewall, with no public address.
  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  # Multi-AZ keeps a standby copy in another AZ for failover (costs about double).
  multi_az = var.db_multi_az

  # How many days of automatic backups to keep.
  backup_retention_period = var.db_backup_retention_days
  # When true, AWS refuses to delete the database (even `terraform destroy`) until you turn
  # it off. Off for practice, on for full scale.
  deletion_protection = var.db_deletion_protection
  # On delete, either skip the last backup (practice) or take one named "<name>-final".
  skip_final_snapshot       = var.db_skip_final_snapshot
  final_snapshot_identifier = var.db_skip_final_snapshot ? null : "${var.name}-final-${random_id.final_snapshot.hex}"

  # Let AWS apply small Postgres updates (e.g. 16.4 -> 16.5) automatically.
  auto_minor_version_upgrade = true
  # true: apply changes straight away. false: wait for the weekly maintenance window (a
  # change such as a new instance class restarts the database, so full scale uses false).
  apply_immediately = var.db_apply_immediately
}
