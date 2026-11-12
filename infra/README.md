# Deploying to AWS

Terraform for a VPC and an RDS Postgres database. The app servers and the load balancer are added in the next change.

```
VPC: 2 public subnets (empty for now) + 2 database subnets -> RDS Postgres 16
```

- **Community module:** the network (VPC, subnets, route tables) uses [terraform-aws-modules/vpc](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws), the way most teams do. Everything else is written by hand so each piece is visible. Run `terraform init` to download it.
- **No NAT gateway:** it costs about $33/month and nothing here needs it.
- **Private database:** it sits in subnets with no route to the internet, behind a security group with no inbound rules yet.
- **Local state:** it contains the DB password, so it is gitignored. A remote backend is a follow-up.

## Prerequisites

- [tfenv](https://github.com/tfutils/tfenv): run `tfenv install` once in the repo; it installs the pinned version from `.terraform-version`.
- An AWS CLI profile that can create the resources (`export AWS_PROFILE=...`).
- The default region is `eu-north-1`. A project account is fixed to the region AWS assigned it, so check AWS Settings > Project.

## Apply and destroy

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # optional: adjust sizes and region
terraform init
terraform apply
terraform destroy
```

Edit `terraform.tfvars` to change sizes or the region (see `variables.tf`). After a destroy, check in the console that nothing is left (RDS snapshots in particular). The defaults skip the final snapshot and turn off deletion protection.

## Cost

About $0.02/hour, roughly $14/month if left running, for the database in `eu-north-1` (Stockholm), the default region: `db.t4g.micro` Single-AZ at $0.016/hour plus 20 GB of gp3 storage at $0.12 per GB-month ($2.40/month). These are on-demand prices from the AWS Price List published 2026-11-12; check the AWS Pricing Calculator for current figures and other regions. Cost alerts are account-wide, so they are not part of this Terraform; set a budget once in the AWS console.
