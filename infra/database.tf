# The Postgres database (Amazon RDS), its firewall and its password.

# A security group is a firewall attached to a resource. This one is for the database and
# starts empty (nothing allowed in). The rule that opens it to the app servers is added
# together with the app servers.
resource "aws_security_group" "db" {
  # AWS requires unique names; `name_prefix` lets AWS add a random suffix.
  name_prefix = "${var.name}-db-"
  description = "Postgres from the app instances only"
  vpc_id      = module.vpc.vpc_id

  # When this must be replaced, create the new one first, then delete the old one.
  # Otherwise the delete fails because the database is still using it.
  lifecycle {
    create_before_destroy = true
  }
}

# A random 32-character password, generated once on the first apply and kept in the state.
# Alphanumeric only, so it can go into DATABASE_URL without escaping.
resource "random_password" "db" {
  length  = 32
  special = false
}

# Stores the password in AWS Systems Manager Parameter Store so the app servers can read it
# at boot. "SecureString" means it is encrypted. The app servers' IAM role is
# allowed to read this one parameter and nothing else.
resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.name}/db_password"
  type  = "SecureString"
  value = random_password.db.result
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
  password = random_password.db.result

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
