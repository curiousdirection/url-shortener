# The network everything lives in.
#
#   VPC (10.0.0.0/16)
#   ├── 2 public subnets   (one per availability zone): the load balancer and app tasks
#   └── 2 database subnets (one per availability zone): the database, no route to the internet
#
# In practice, teams rarely write a VPC by hand. This uses the community module
# terraform-aws-modules/vpc/aws, which creates all of the pieces below from a few inputs:
#   docs:   https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws
#   source: https://github.com/terraform-aws-modules/terraform-aws-vpc
#   - the VPC itself (with DNS names switched on)
#   - the subnets, in the availability zones listed in `azs`
#   - an internet gateway (the door between the VPC and the internet)
#   - a route table sending internet-bound traffic from the public subnets to that gateway;
#     that route is what makes a subnet "public"
#   - the RDS subnet group (tells RDS which subnets it may use), exposed as
#     module.vpc.database_subnet_group_name
#
# To see what the module does for you, these are the AWS provider resources it wraps:
#   aws_vpc               https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc
#   aws_subnet            https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet
#   aws_internet_gateway  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway
#   aws_route_table       https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table
#   aws_db_subnet_group   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group

# An availability zone (AZ) is a separate data center inside the region. This looks up the
# ones that are currently usable.
data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  # Any 6.x release, but not 7.0. Modules are versioned like providers; major versions can
  # rename inputs.
  version = "~> 6.0"

  name = var.name
  # The range of private IP addresses the VPC can hand out (about 65,000).
  cidr = "10.0.0.0/16"
  # The first two AZ names, e.g. ["eu-north-1a", "eu-north-1b"]. Spreading across two AZs
  # means one data center failing doesn't take everything down.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # One subnet per AZ, in order: each is a /24 block (256 addresses). The public ones hold
  # the load balancer and app tasks. The database ones hold RDS, which needs subnets in
  # at least two AZs.
  public_subnets   = ["10.0.0.0/24", "10.0.1.0/24"]
  database_subnets = ["10.0.10.0/24", "10.0.11.0/24"]

  # No NAT gateway (see "Cost" in README.md): Express Mode gives tasks in public subnets a
  # public IP for outbound traffic, and only the load balancer can reach them.
  enable_nat_gateway = false
  # The module also builds an IPv6 outbound-only gateway by default; we don't use IPv6.
  create_egress_only_igw = false
}
