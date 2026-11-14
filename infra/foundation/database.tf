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
#
# Only the parameter below uses this fresh value. The database does not: it takes whatever
# the parameter holds (see "How the two stay the same" below).
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
}

# How the two stay the same
# -------------------------
# The database and the parameter must always hold the same password. Neither can be read back
# from the state, so Terraform can't compare them. Two rules make them equal by construction:
#
#   1. The parameter is the one source. It is the only place a fresh password is written.
#   2. The database never gets a password of its own. Whenever it is written, in the same
#      run, it is handed what the parameter holds at that moment (the block below).
#
# Rule 2 covers the database being created or replaced at any time: it reads the parameter,
# so it can't start with a different password. For the other direction (the parameter being
# written when the database is not), `terraform_data.db_password_written` below changes
# whenever the parameter is created or written, and the database lists it as its
# `password_wo_version`. So a new parameter always means "send the database the password
# again". The cases:
#
#   - First apply: the parameter, then the marker, then the database. If it stops half way,
#     the next apply carries on from there. The database is never made before the parameter.
#   - Parameter deleted outside Terraform (the console, a failed destroy): the next apply
#     creates it with a new password, replaces the marker, and updates the database to match.
#   - Parameter changed outside Terraform: its version number changes, which replaces the
#     marker, so the database is updated to the parameter's current value.
#   - Database deleted or replaced: it is created with the parameter's password. The parameter
#     is untouched, so running tasks keep working.
#   - New password (db_password_version raised): the parameter is written, then the database.
#
# The one gap is a run that is killed in the few milliseconds between writing the parameter
# and saving the marker. If you ever think they differ, raise db_password_version by one and
# apply: that writes a new password to both (see "Rotate the database password" in
# infra/README.md).
#
# Reading the parameter needs ssm:GetParameter and kms:Decrypt for the person who applies
# the foundation. The pull request plan role is denied both on purpose; CI never plans this
# stack.
#   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/ephemeral-resources/ssm_parameter
ephemeral "aws_ssm_parameter" "db_password" {
  # Using the ARN makes Terraform wait until the parameter has been written before it reads
  # it. While the parameter doesn't exist yet the ARN is unknown, so Terraform postpones the
  # read to the apply, after the parameter is created.
  arn = aws_ssm_parameter.db_password.arn
}

# A marker that changes whenever the parameter is created or written, so the database knows
# to be sent the password again. `terraform_data` is built into Terraform (no provider).
#   - `triggers_replace`: the parameter's version number is unknown while the parameter is
#     about to be created, which replaces the marker. It also changes when the parameter is
#     changed outside Terraform.
#   - `replace_triggered_by`: replaces the marker when the parameter is updated (a new
#     db_password_version). It does not fire when the parameter is created, which is why
#     `triggers_replace` is there too.
#   - `input` is the time the marker was made, as a number (for example 20261114153000).
#     `ignore_changes` stops it from changing on every plan, so it only changes when the
#     marker is replaced. Time only goes forward, so the number is never reused.
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
  # The password the parameter holds, read while Terraform runs. It is sent when the database
  # is created, and again whenever the marker changes (so whenever the parameter is written).
  # See "How the two stay the same" above.
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
