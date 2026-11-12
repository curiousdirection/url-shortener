# The load balancer: the single public entry point. It accepts requests from the internet
# and spreads them across the healthy app servers.
#
#   internet -> NLB (:80, and :443 if a domain is set) -> app servers (:3000)
#
# NLB (Network Load Balancer) rather than ALB: at this scale almost every click is a new
# connection, and ALB's per-capacity-unit new-connection limit (25/s) would cost ~10x more.

# Firewall for the load balancer: the internet may connect on port 80...
resource "aws_security_group" "nlb" {
  name_prefix = "${var.name}-nlb-"
  description = "Public HTTP(S) into the NLB"
  vpc_id      = aws_vpc.main.id

  lifecycle {
    create_before_destroy = true
  }
}

# ...from anywhere (0.0.0.0/0 means every IPv4 address).
resource "aws_vpc_security_group_ingress_rule" "nlb_http" {
  security_group_id = aws_security_group.nlb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

# Port 443 (HTTPS) is opened only when a domain is set. `count` is 1 when TLS is on and 0
# when off; with 0, Terraform creates nothing.
resource "aws_vpc_security_group_ingress_rule" "nlb_https" {
  count = local.tls_enabled ? 1 : 0

  security_group_id = aws_security_group.nlb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# The load balancer may only send traffic out to the app servers, on port 3000.
resource "aws_vpc_security_group_egress_rule" "nlb_to_app" {
  security_group_id            = aws_security_group.nlb.id
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
}

# The load balancer itself, placed in the two public subnets (one address per AZ).
resource "aws_lb" "main" {
  name               = var.name
  load_balancer_type = "network"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.nlb.id]

  # Let each load balancer node send traffic to servers in either AZ, so the load stays
  # even if the servers are unevenly spread.
  enable_cross_zone_load_balancing = true
}

# The pool of servers the load balancer sends traffic to. Servers join and leave it
# automatically (the auto scaling group in app.tf registers them).
resource "aws_lb_target_group" "app" {
  name_prefix = "app-"
  vpc_id      = aws_vpc.main.id
  protocol    = "TCP"
  port        = 3000

  # When a server is removed, wait up to 30 s for its open connections to finish before
  # cutting it off. The app's own shutdown handler (src/server.ts) is sized to fit this.
  deregistration_delay = 30

  # The load balancer calls GET /health on each server every 10 s. 3 passes in a row mark
  # it healthy (traffic starts), 3 failures in a row mark it unhealthy (traffic stops, and
  # the auto scaling group replaces it).
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

# "Listen on port 80 and forward everything to the target group."
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  protocol          = "TCP"
  port              = 80

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# Optional TLS (HTTPS) on :443. Everything below is created only when `domain_name` is set
# (`count = 0` otherwise). TLS ends at the load balancer; traffic to the servers is plain HTTP.

# Requests a free certificate for the domain from AWS Certificate Manager (ACM). ACM
# checks you own the domain by looking for a special DNS record ("DNS validation").
resource "aws_acm_certificate" "main" {
  count = local.tls_enabled ? 1 : 0

  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Creates that special DNS record in your Route 53 hosted zone. `for_each` makes one record
# per validation entry ACM asks for (normally one).
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

# Waits until ACM has seen the DNS record and issued the certificate. Anything that needs
# a working certificate (the HTTPS listener) refers to this, not to the certificate itself.
resource "aws_acm_certificate_validation" "main" {
  count = local.tls_enabled ? 1 : 0

  certificate_arn         = aws_acm_certificate.main[0].arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# "Listen on port 443, decrypt with the certificate, forward to the same target group."
resource "aws_lb_listener" "https" {
  count = local.tls_enabled ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  protocol          = "TLS"
  port              = 443
  certificate_arn   = aws_acm_certificate_validation.main[0].certificate_arn
  # Which TLS versions and ciphers to accept (TLS 1.2 and 1.3).
  ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# Points your domain name at the load balancer (an "alias" record in Route 53).
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
