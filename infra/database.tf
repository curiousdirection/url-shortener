# The Postgres database (Amazon Aurora PostgreSQL), its firewall and its password.

# A security group is a firewall attached to a resource. This one is for the database. The only
# rule that lets anything in is db_from_app in app.tf.
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

# A random 32-character password, generated once on the first apply and kept in the state.
# Alphanumeric only, so it never needs escaping.
resource "random_password" "db" {
  length  = 32
  special = false
}

# The user name and password, as JSON in AWS Secrets Manager. ECS reads the password from it
# when it starts a task and passes it in as PGPASSWORD (see app.tf). The Data API takes the
# same secret (`aws rds-data execute-statement --secret-arn ...`), so there is one copy. It
# is not an RDS-managed secret, because those rotate every 7 days and running tasks would
# keep the old password. The name starts with rds-db-credentials/ because the query editor
# policy in the AWS docs only allows secrets with that prefix.
resource "aws_secretsmanager_secret" "db" {
  name = "rds-db-credentials/${var.name}"
  # Delete at once on destroy. Otherwise the name stays reserved for 30 days and the next
  # apply fails.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = aws_rds_cluster.main.master_username
    password = random_password.db.result
  })
}

# A random suffix for the final snapshot's name. Snapshot names must be unique, so a fixed
# name would make a second destroy fail while the first snapshot still exists. A new suffix
# is generated each time the stack is created.
resource "random_id" "final_snapshot" {
  byte_length = 4
}

# The cluster: the shared storage, the endpoints and the settings. The database servers are
# the instances below.
resource "aws_rds_cluster" "main" {
  cluster_identifier = var.name
  engine             = "aurora-postgresql"
  # "16" means the latest 16.x minor version. Pausing needs 16.3 or later, and Aurora no
  # longer offers anything older than 16.8.
  engine_version = "16"

  database_name   = "urlshortener"
  master_username = "urlshortener"
  master_password = random_password.db.result

  # Aurora grows the storage by itself, so there is no size to set. Encrypted at rest.
  storage_encrypted = true

  # Place it in the database subnets (and subnet group) created by the VPC module, behind the
  # database firewall.
  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.db.id]

  # The Data API: lets the RDS console's query editor and `aws rds-data` run SQL without a
  # network path into the VPC. Callers still need IAM permission and the password.
  enable_http_endpoint = true

  # The size range every serverless instance scales within. Used when db_instance_class is
  # db.serverless; not used otherwise. With a minimum of 0, an instance with no connections
  # for 5 minutes pauses and costs nothing until the next connection (see "Cost" in
  # README.md).
  serverlessv2_scaling_configuration {
    min_capacity             = var.db_min_capacity
    max_capacity             = var.db_max_capacity
    seconds_until_auto_pause = 300
  }

  # How many days of automatic backups to keep.
  backup_retention_period = var.db_backup_retention_days
  # When true, AWS refuses to delete the database (even `terraform destroy`) until you turn
  # it off. Off for practice, on for full scale.
  deletion_protection = var.db_deletion_protection
  # On delete, either skip the last backup (practice) or take one named "<name>-final".
  skip_final_snapshot       = var.db_skip_final_snapshot
  final_snapshot_identifier = var.db_skip_final_snapshot ? null : "${var.name}-final-${random_id.final_snapshot.hex}"

  # true: apply changes straight away. false: wait for the weekly maintenance window (a
  # change such as a new instance class restarts the database, so full scale uses false).
  apply_immediately = var.db_apply_immediately
}

# The database servers in the cluster: one writer, and with more than one instance, readers
# that take over if the writer fails.
resource "aws_rds_cluster_instance" "main" {
  count              = var.db_instances
  identifier         = "${var.name}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.main.id
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version
  # db.serverless (see variables.tf) or a fixed size such as db.r7g.large.
  instance_class = var.db_instance_class

  db_subnet_group_name = aws_rds_cluster.main.db_subnet_group_name
  publicly_accessible  = false

  # Let AWS apply small Postgres updates (e.g. 16.9 -> 16.10) automatically.
  auto_minor_version_upgrade = true
  apply_immediately          = var.db_apply_immediately
}
