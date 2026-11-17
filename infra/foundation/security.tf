# The app's firewall group, and the one rule that lets it reach the database.

# Attached to the tasks next to the security groups Express Mode creates (which let the load
# balancer in), so the DB rule below applies to the tasks. The app stack passes its id to ECS.
resource "aws_security_group" "app" {
  name_prefix = "${var.name}-app-"
  description = "App tasks: outbound only"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# The database accepts Postgres connections from the app group and from nothing else. This
# must exist before the first task starts, because the task runs migrations on startup.
resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
