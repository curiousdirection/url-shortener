data "aws_caller_identity" "current" {}

data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

# Key behind the default "aws/ssm" alias, used to encrypt the SecureString.
data "aws_kms_alias" "ssm" {
  name = "alias/aws/ssm"
}

# Releases

resource "aws_s3_bucket" "releases" {
  bucket        = "${var.name}-releases-${data.aws_caller_identity.current.account_id}-${var.region}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "releases" {
  bucket                  = aws_s3_bucket.releases.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Instance role: SSM Session Manager (no SSH), release download, DB password.

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

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

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
  }
}

resource "aws_iam_role_policy" "app" {
  name   = "app"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app.json
}

resource "aws_iam_instance_profile" "app" {
  name_prefix = "${var.name}-app-"
  role        = aws_iam_role.app.name
}

# Instances

resource "aws_security_group" "app" {
  name_prefix = "${var.name}-app-"
  description = "App port from the NLB only; no SSH (use SSM Session Manager)"
  vpc_id      = aws_vpc.main.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_nlb" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.nlb.id
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
}

resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

locals {
  tls_enabled = var.domain_name != null
  base_url    = local.tls_enabled ? "https://${var.domain_name}" : "http://${aws_lb.main.dns_name}"
}

resource "aws_launch_template" "app" {
  name_prefix   = "${var.name}-"
  image_id      = data.aws_ssm_parameter.al2023_arm64.value
  instance_type = var.instance_type

  update_default_version = true

  iam_instance_profile {
    arn = aws_iam_instance_profile.app.arn
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.app.id]
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

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

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = var.name }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "app" {
  name_prefix         = "${var.name}-"
  vpc_zone_identifier = aws_subnet.public[*].id
  min_size            = var.asg_min
  max_size            = var.asg_max
  desired_capacity    = var.asg_desired

  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 120

  # Make the first apply wait until targets are healthy, so a broken boot fails loudly.
  min_elb_capacity          = var.asg_min
  wait_for_capacity_timeout = "10m"

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  # A new launch template version (new app_version, new AMI) rolls the instances.
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 100
      max_healthy_percentage = 200
      instance_warmup        = 120
    }
  }

  tag {
    key                 = "Name"
    value               = var.name
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }
}

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
