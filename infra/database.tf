# The Postgres database (Amazon RDS), its firewall and its password.
#
# The database server uses the community module terraform-aws-modules/rds/aws. The firewall
# and the password stay hand-written, because they are specific to this project.
# Docs: https://registry.terraform.io/modules/terraform-aws-modules/rds/aws

# A security group is a firewall attached to a resource. This one is for the database and
# starts empty (nothing allowed in). The rule that opens it is a separate resource below.
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

# Allow Postgres (port 5432) into the database, but only from resources that are members
# of the app security group. It names a group, not IP addresses, so it keeps working as
# app instances come and go.
resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

# A random 32-character password, generated once on the first apply and kept in the state.
# Alphanumeric only, so it can go into DATABASE_URL without escaping.
resource "random_password" "db" {
  length  = 32
  special = false
}

# Stores the password in AWS Systems Manager Parameter Store so the app servers can read it
# at boot. "SecureString" means it is encrypted. The servers' IAM role (see app.tf) is
# allowed to read this one parameter and nothing else.
resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.name}/db_password"
  type  = "SecureString"
  value = random_password.db.result
}

# The database server itself.
module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 7.0"

  identifier = var.name
  engine     = "postgres"
  # "16" means the latest 16.x minor version. `family` names the matching parameter group
  # (Postgres settings), which the module creates for us.
  engine_version = "16"
  family         = "postgres16"
  # The machine size, e.g. db.t4g.micro (see variables.tf).
  instance_class = var.db_instance_class

  db_name  = "urlshortener"
  username = "urlshortener"
  # We bring our own password. By default this module would ask RDS to create one in
  # Secrets Manager instead, but those rotate every 7 days by default, which would break
  # the connection string the app reads at boot.
  manage_master_user_password = false
  # "Write-only": sent to AWS but not saved in the state by the database resource. Needs
  # Terraform 1.11 or newer. Bump the version number to push a changed password.
  password_wo         = random_password.db.result
  password_wo_version = 1

  # Disk size in GiB. gp3 is general-purpose SSD storage. Encrypted at rest.
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  # Place it in the database subnets (created by the VPC module), behind the database
  # firewall, with no public address.
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
  # On delete, either skip the last backup (practice) or keep one named final-<name>-<id>.
  skip_final_snapshot = var.db_skip_final_snapshot

  # Let AWS apply small Postgres updates (e.g. 16.4 -> 16.5) automatically.
  auto_minor_version_upgrade = true
  # Apply changes straight away instead of waiting for the weekly maintenance window.
  apply_immediately = true
}
