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

# The database password, kept out of the plan, the state and the logs. It is generated in
# memory on every run (ephemeral) and sent only through write-only arguments (`*_wo`), which
# Terraform never stores. Alphanumeric only, so it never needs escaping.
#   https://developer.hashicorp.com/terraform/language/block/ephemeral
ephemeral "random_password" "db" {
  length  = 32
  special = false
}

# The one place the password is stored, encrypted. ECS reads it when a task starts and passes
# it in as PGPASSWORD. Terraform can't see the stored value, so it only writes a new one when
# `value_wo_version` changes (or the parameter is created).
resource "aws_ssm_parameter" "db_password" {
  name             = "/${var.name}/db_password"
  type             = "SecureString"
  value_wo         = ephemeral.random_password.db.result
  value_wo_version = var.db_password_version
}

# The database never gets a password of its own: it is always given what the parameter holds,
# read back here. So a new or replaced database matches the parameter, and the marker below
# makes sure the database is updated whenever the parameter is written. The one gap is a run
# killed between those two writes; raising db_password_version fixes it. Reading the
# parameter needs ssm:GetParameter and kms:Decrypt, which is why CI never plans this stack.
ephemeral "aws_ssm_parameter" "db_password" {
  arn = aws_ssm_parameter.db_password.arn
}

# Replaced whenever the parameter is created or written (`triggers_replace` catches creation,
# `replace_triggered_by` catches updates). Its output, a timestamp, is the database's
# `password_wo_version`, so a new value means "send the database the password again".
resource "terraform_data" "db_password_written" {
  triggers_replace = [aws_ssm_parameter.db_password.version]
  input            = parseint(formatdate("YYYYMMDDhhmmss", timestamp()), 10)

  lifecycle {
    ignore_changes       = [input]
    replace_triggered_by = [aws_ssm_parameter.db_password]
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
  # What the parameter holds; sent again whenever the marker changes (see above).
  password_wo         = ephemeral.aws_ssm_parameter.db_password.value
  password_wo_version = terraform_data.db_password_written.output

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
