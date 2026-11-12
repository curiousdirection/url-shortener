# The load balancer: the single public entry point. It accepts requests from the internet
# and spreads them across the healthy app servers.
#
#   internet -> NLB (:80) -> app servers (:3000)
#
# NLB (Network Load Balancer) rather than ALB (Application Load Balancer): at this scale almost every click is a new
# connection, and ALB's per-capacity-unit new-connection limit (25/s) would cost ~10x more.
#
# This uses the community module terraform-aws-modules/alb/aws, which builds both
# Application and Network load balancers (`load_balancer_type` picks which). From the
# inputs below it creates the load balancer, its firewall, the listener and the target
# group. Docs: https://registry.terraform.io/modules/terraform-aws-modules/alb/aws
module "nlb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 10.0"

  name               = var.name
  load_balancer_type = "network"
  vpc_id             = module.vpc.vpc_id
  # Placed in the two public subnets (one address per AZ).
  subnets = module.vpc.public_subnets

  # Let each load balancer node send traffic to servers in either AZ, so the load stays
  # even if the servers are unevenly spread.
  enable_cross_zone_load_balancing = true
  # The module turns this on by default, which would make `terraform destroy` fail.
  enable_deletion_protection = false

  # Firewall for the load balancer, created by the module: the internet may connect on
  # port 80 (0.0.0.0/0 means every IPv4 address), and the load balancer may only send
  # traffic out to the app servers, on port 3000.
  security_group_ingress_rules = {
    http = {
      description = "HTTP from the internet"
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
  security_group_egress_rules = {
    app = {
      description                  = "To the app servers"
      from_port                    = 3000
      to_port                      = 3000
      ip_protocol                  = "tcp"
      referenced_security_group_id = aws_security_group.app.id
    }
  }

  # "Listen on port 80 and forward everything to the target group named `app` below."
  listeners = {
    http = {
      port     = 80
      protocol = "TCP"
      forward = {
        target_group_key = "app"
      }
    }
  }

  # The pool of servers the load balancer sends traffic to. The auto scaling group (see
  # app.tf) registers servers in it, so the module has nothing to attach itself.
  target_groups = {
    app = {
      name_prefix       = "app-"
      protocol          = "TCP"
      port              = 3000
      target_type       = "instance"
      create_attachment = false

      # When a server is removed, wait up to 30 s for its open connections to finish before
      # cutting it off. The app's own shutdown handler (src/server.ts) is sized to fit this.
      deregistration_delay = 30

      # The load balancer calls GET /health on each server every 10 s. 3 passes in a row
      # mark it healthy (traffic starts), 3 failures in a row mark it unhealthy (traffic
      # stops, and the auto scaling group replaces it).
      health_check = {
        enabled             = true
        protocol            = "HTTP"
        path                = "/health"
        port                = "traffic-port"
        interval            = 10
        healthy_threshold   = 3
        unhealthy_threshold = 3
        matcher             = "200"
      }
    }
  }
}
