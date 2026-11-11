# Deploying to AWS

Terraform for a practice deployment that has the same structure as the full-scale design, so only variable values differ (`terraform.tfvars.example` vs `full-scale.tfvars.example`).

```
Internet -> NLB (2 public subnets) -> Auto Scaling group of EC2 (:3000) -> RDS Postgres 16 (private subnets)
```

- **NLB, not ALB:** at ~11,600 new connections/s, ALB capacity units would cost ~$2,700/month against ~$290 for the NLB.
- **No NAT gateway, no API Gateway, no Lambda:** instances sit in public subnets with a public IP and accept only the NLB's security group.
- **No SSH:** use SSM Session Manager.
- **Local state:** it contains the DB password, so it is gitignored. A remote backend is a follow-up.

## Prerequisites

- Terraform >= 1.9, AWS CLI with a profile that can create the resources (`export AWS_PROFILE=...`), Node, git.

## First deploy

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # set budget_alert_email
terraform init
terraform apply -target=aws_s3_bucket.releases   # the bucket must exist before the first release
./scripts/release.sh                             # prints the next command
terraform apply -var app_version=<printed version>
```

Then:

```bash
curl http://$(terraform output -raw nlb_dns_name)/health
```

The first apply waits up to 10 minutes for the targets to become healthy. If it times out, open a session with `aws ssm start-session --target <instance-id>` and read `/var/log/user-data.log`.

## Releasing

Commit, run `infra/scripts/release.sh`, then run the `terraform apply -var app_version=...` it prints. The new `app_version` changes the launch template, so the ASG replaces instances one at a time without dropping capacity. A new Amazon Linux AMI also triggers a refresh on the next apply.

## Scaling

`asg_desired` only sets the initial size; the ASG ignores later changes so autoscaling (target 60% CPU) and manual scaling are not undone:

```bash
aws autoscaling set-desired-capacity --auto-scaling-group-name <name> --desired-capacity 2
```

## TLS (optional)

Set `domain_name` and `route53_zone_id`. Terraform requests an ACM certificate, validates it through Route 53, adds a :443 listener and an alias record, and `BASE_URL` becomes `https://<domain_name>`.

## Tear down

```bash
terraform destroy
```

Then check in the console that nothing is left (Elastic IPs, RDS snapshots, the S3 bucket). The practice defaults skip the final snapshot and turn off deletion protection; full-scale values do the opposite.

## Cost (on-demand us-east-1; check with the AWS Pricing Calculator)

Practice, always on: about $0.07/hour, about $52/month (NLB ~$0.039/h, t4g.micro ~$0.014/h, db.t4g.micro ~$0.019/h). At 10 hours a week with `terraform destroy` in between, a few dollars a month. `budget.tf` emails you at 80% of `budget_limit_usd` (actual) and 100% (forecast).

Full scale: about $4,000/month (data transfer out ~$2,660, RDS ~$630, servers ~$370, NLB ~$290, IPv4 ~$40). Don't send per-request logs to CloudWatch: ~200 GB/day would add ~$3,000/month.
