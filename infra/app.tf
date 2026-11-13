# The app servers: where the code is stored, what the servers are allowed to do, and the
# auto scaling group that keeps the right number of them running.
#
#   release.sh -> S3 bucket -> (each server downloads it at boot, see user_data.sh.tftpl)

# Your AWS account id; used below to make the bucket name unique.
data "aws_caller_identity" "current" {}

# AWS publishes the id of the newest Amazon Linux 2023 (Arm) image as a public parameter.
# Reading it means new servers always start from a current, patched image. (A new image
# changes the launch template and rolls the servers on your next apply.)
#
# The launch template below reads `insecure_value`, not `value`. Both hold the same image id.
# The difference is only in what `terraform plan` shows: Terraform assumes a parameter
# could be a password, so it prints `value` as "(sensitive value)". This parameter is a
# public image id, so there is nothing to hide, and with `insecure_value` the plan shows the
# old and new ids when AWS publishes a new image (the change that replaces every server).
data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

# Key behind the default "aws/ssm" alias, used to encrypt the SecureString.
data "aws_kms_alias" "ssm" {
  name = "alias/aws/ssm"

  # AWS creates this managed key on the first SecureString, so read it after the parameter exists.
  depends_on = [aws_ssm_parameter.db_password]
}

# Releases

# The bucket scripts/release.sh uploads each build to. Bucket names are global across all of
# AWS, so the account id and region are part of the name. `force_destroy` lets
# `terraform destroy` delete the bucket even if it still contains releases.
resource "aws_s3_bucket" "releases" {
  bucket        = "${var.name}-releases-${data.aws_caller_identity.current.account_id}-${var.region}"
  force_destroy = true
}

# Belt and braces: block every way of making this bucket public.
resource "aws_s3_bucket_public_access_block" "releases" {
  bucket                  = aws_s3_bucket.releases.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Instance role: SSM Session Manager (no SSH), release download, DB password.
#
# An IAM role is a set of permissions that AWS resources can take on, instead of storing
# access keys on the server. Two parts: who may use the role ("trust"), and what it may do.

# Trust: the EC2 service may assume this role (that is, servers may use it).
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name_prefix        = "${var.name}-app-"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# An AWS-managed policy that lets the server register with Systems Manager, which is how
# you open a shell on it (Session Manager) without SSH or an open port 22.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# What the servers may do, kept as narrow as possible:
#  - download files under releases/ in the bucket
#  - read the one parameter holding the DB password
#  - decrypt with the key SSM uses, and only when going through SSM
data "aws_iam_policy_document" "app" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.releases.arn}/releases/*"]
  }
  statement {
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.db_password.arn]
  }
  statement {
    actions   = ["kms:Decrypt"]
    resources = [data.aws_kms_alias.ssm.target_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "app" {
  name   = "app"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app.json
}

# EC2 attaches roles to servers through an "instance profile", a thin wrapper around the role.
resource "aws_iam_instance_profile" "app" {
  name_prefix = "${var.name}-app-"
  role        = aws_iam_role.app.name
}

# Instances

# Firewall for the app servers. It starts closed; the rules below open exactly one door.
resource "aws_security_group" "app" {
  name_prefix = "${var.name}-app-"
  description = "App port from the NLB only; no SSH (use SSM Session Manager)"
  vpc_id      = module.vpc.vpc_id

  lifecycle {
    create_before_destroy = true
  }
}

# The only inbound traffic allowed: port 3000 (the app) from the load balancer.
resource "aws_vpc_security_group_ingress_rule" "app_from_nlb" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.nlb.id
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
}

# Outbound traffic is unrestricted (`-1` = all protocols). Servers need it to reach S3,
# SSM, the database and the Node and npm downloads at boot.
resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# Allow Postgres (port 5432) into the database, but only from resources that are members of
# the app security group. It names a group, not IP addresses, so it keeps working as app
# instances come and go.
resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

locals {
  # The provider's default_tags don't reach instances and disks launched by the auto scaling
  # group, so the launch template tags them itself (used in billing reports).
  launch_tags = { Project = var.name, ManagedBy = "terraform" }

  # The address the app puts in the short links it returns.
  base_url = "http://${aws_lb.main.dns_name}"
}

# A launch template is the recipe for one app server: which image, what size, which role,
# which firewall and which boot script. The auto scaling group stamps out servers from it.
resource "aws_launch_template" "app" {
  name_prefix   = "${var.name}-"
  image_id      = data.aws_ssm_parameter.al2023_arm64.insecure_value
  instance_type = var.instance_type

  # Each change creates a new numbered version; make the newest one the default.
  update_default_version = true

  iam_instance_profile {
    arn = aws_iam_instance_profile.app.arn
  }

  # 1-minute metrics so target tracking reacts quickly (small extra cost per instance).
  monitoring {
    enabled = true
  }

  # IMDSv2 only: code on the server must fetch a session token before reading its own
  # credentials. This blocks a class of attacks where a bug in an app tricks it into
  # leaking them.
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  # Give each server a public IP (so it can reach the internet without a NAT gateway) and
  # attach the app firewall.
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.app.id]
  }

  # The server's disk: 8 GiB, encrypted, deleted together with the server.
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # The boot script (user_data.sh.tftpl) with the values filled in. It runs once when each
  # server first starts. Changing anything in it (for example `app_version`) creates a new
  # launch template version, which makes the auto scaling group replace the servers.
  user_data = base64encode(templatefile("${path.module}/user_data.sh.tftpl", {
    region                = var.region
    bucket                = aws_s3_bucket.releases.id
    app_version           = var.app_version
    base_url              = local.base_url
    db_endpoint           = aws_db_instance.main.address
    db_name               = aws_db_instance.main.db_name
    db_user               = aws_db_instance.main.username
    db_password_parameter = aws_ssm_parameter.db_password.name
  }))

  # Name and tag the servers, and tag their disks.
  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.launch_tags, { Name = var.name })
  }
  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.launch_tags, { Name = var.name })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# The auto scaling group (ASG): keeps between asg_min and asg_max servers running, replaces
# any that fail, and adds or removes servers as load changes.
resource "aws_autoscaling_group" "app" {
  name_prefix = "${var.name}-"
  # Start servers in the public subnets, spread across both AZs.
  vpc_zone_identifier = module.vpc.public_subnets
  min_size            = var.asg_min
  max_size            = var.asg_max
  desired_capacity    = var.asg_desired

  # Register new servers with the load balancer's target group. Use the load balancer's
  # health check (not just "is the machine on") to decide whether a server is healthy.
  target_group_arns = [aws_lb_target_group.app.arn]
  health_check_type = "ELB"
  # Instances join the NLB before user data runs: boot (~60-90 s) plus 3 health checks (30 s)
  # must fit in this, or the ASG replaces them in a loop.
  health_check_grace_period = 300

  # Keep a booting instance's CPU out of the scaling average.
  default_instance_warmup = 120

  # Publish group-level metrics (how many servers are in service, pending and so on).
  enabled_metrics     = ["GroupDesiredCapacity", "GroupInServiceInstances", "GroupPendingInstances", "GroupTerminatingInstances", "GroupTotalInstances"]
  metrics_granularity = "1Minute"

  # Make the first apply wait until targets are healthy, so a broken boot fails loudly.
  min_elb_capacity          = var.asg_min
  wait_for_capacity_timeout = "10m"

  # Which recipe to use. Pinning the exact version number is what lets a rollback work.
  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  # A new launch template version (new app_version, new AMI) rolls the instances.
  # "Rolling" replaces servers gradually. Min healthy 100% / max 200% means: start the new
  # server first (up to double the normal count), and only remove an old one once it works,
  # so capacity never dips.
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 100
      max_healthy_percentage = 200
      instance_warmup        = 300
      # Roll back to the previous launch template version if a release never gets healthy.
      auto_rollback = true
    }
  }

  lifecycle {
    create_before_destroy = true
    # The scaling policy and manual changes move the desired count. Without this, the next
    # `terraform apply` would reset it to asg_desired.
    ignore_changes = [desired_capacity]
  }
}

# Autoscaling rule: add servers when average CPU rises above 60%, remove them when it falls
# well below ("target tracking" keeps the average near the target).
resource "aws_autoscaling_policy" "cpu" {
  name                   = "${var.name}-cpu-60"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60
  }
}
