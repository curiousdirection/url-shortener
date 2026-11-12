# The load balancer: the single public entry point. It accepts requests from the internet
# and spreads them across the healthy app servers.
#
#   internet -> NLB (:80) -> app servers (:3000)
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
