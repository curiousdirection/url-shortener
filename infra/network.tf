# The network everything lives in.
#
#   VPC (10.0.0.0/16)
#   ├── 2 public subnets  (one per availability zone): the load balancer and app servers
#   └── 2 private subnets (one per availability zone): the database
#
# "Public" vs "private" is decided by the route table (see aws_route_table.public below).

# An availability zone (AZ) is a separate data center inside the region. This looks up the
# ones that are currently usable.
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # The first two AZ names, e.g. ["eu-north-1a", "eu-north-1b"]. Spreading across two AZs
  # means one data center failing doesn't take everything down.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

# The VPC is our own private network inside AWS. 10.0.0.0/16 is the range of private IP
# addresses it can hand out (about 65,000).
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  # Let things inside look each other up by DNS name (e.g. the database's address).
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.name }
}

# The door between the VPC and the internet. Without it, nothing in the VPC can reach
# the internet or be reached from it.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = var.name }
}

# No NAT gateway (it costs about $33/month): app instances get a public IP for outbound
# traffic, and their security group only accepts traffic from the load balancer.
resource "aws_subnet" "public" {
  # `count = 2` makes two copies of this resource. Inside it, `count.index` is 0 for the
  # first copy and 1 for the second, so each one goes in a different AZ.
  count = 2

  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  # Carve a /24 block (256 addresses) out of the VPC range: copy 0 gets 10.0.0.0/24 and
  # copy 1 gets 10.0.1.0/24. `8` is how many bits longer the prefix gets (/16 -> /24).
  cidr_block = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  # Anything launched here gets a public IP address automatically.
  map_public_ip_on_launch = true

  tags = { Name = "${var.name}-public-${local.azs[count.index]}" }
}

# Private subnets are for the database. They get a different block (10.0.10.0/24 and
# 10.0.11.0/24, hence `count.index + 10`) and have no route to the internet gateway, so
# nothing outside the VPC can reach them. RDS needs subnets in at least two AZs.
resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 10)

  tags = { Name = "${var.name}-private-${local.azs[count.index]}" }
}

# A route table is a list of rules saying where traffic goes. This one says: anything not
# for the VPC itself (0.0.0.0/0 means "everywhere else") goes to the internet gateway.
# A subnet using this table is what makes it "public". The private subnets don't use it;
# they keep the VPC's default table, which only has routes inside the VPC.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.name}-public" }
}

# Attaches the public route table to each public subnet (two copies, one per subnet).
resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
