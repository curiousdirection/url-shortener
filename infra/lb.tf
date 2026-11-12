# NLB rather than ALB: at this scale almost every click is a new connection, and
# ALB's per-capacity-unit new-connection limit (25/s) would cost ~10x more.

resource "aws_security_group" "nlb" {
  name_prefix = "${var.name}-nlb-"
  description = "Public HTTP(S) into the NLB"
  vpc_id      = aws_vpc.main.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "nlb_http" {
  security_group_id = aws_security_group.nlb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "nlb_https" {
  count = local.tls_enabled ? 1 : 0

  security_group_id = aws_security_group.nlb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "nlb_to_app" {
  security_group_id            = aws_security_group.nlb.id
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
}

resource "aws_lb" "main" {
  name               = var.name
  load_balancer_type = "network"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.nlb.id]

  enable_cross_zone_load_balancing = true
}

resource "aws_lb_target_group" "app" {
  name_prefix = "app-"
  vpc_id      = aws_vpc.main.id
  protocol    = "TCP"
  port        = 3000

  deregistration_delay = 30

  health_check {
    protocol            = "HTTP"
    path                = "/health"
    port                = "traffic-port"
    interval            = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  protocol          = "TCP"
  port              = 80

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# Optional TLS on :443

resource "aws_acm_certificate" "main" {
  count = local.tls_enabled ? 1 : 0

  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = local.tls_enabled ? {
    for o in aws_acm_certificate.main[0].domain_validation_options : o.domain_name => o
  } : {}

  zone_id         = var.route53_zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "main" {
  count = local.tls_enabled ? 1 : 0

  certificate_arn         = aws_acm_certificate.main[0].arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

resource "aws_lb_listener" "https" {
  count = local.tls_enabled ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  protocol          = "TLS"
  port              = 443
  certificate_arn   = aws_acm_certificate_validation.main[0].certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_route53_record" "alias" {
  count = local.tls_enabled ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}
