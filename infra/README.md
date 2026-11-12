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
cp terraform.tfvars.example terraform.tfvars   # optional: adjust sizes and region
terraform init
terraform apply -target=aws_s3_bucket.releases -var app_version=none   # the bucket must exist before the first release
./scripts/release.sh                             # prints the next command
terraform apply -var app_version=<printed version>
```

Then:

```bash
curl http://$(terraform output -raw nlb_dns_name)/health
```

The first apply waits up to 10 minutes for the targets to become healthy. If it times out, open a session with `aws ssm start-session --target <instance-id>` and read `/var/log/user-data.log`.

## Releasing

Commit, run `infra/scripts/release.sh`, then run the `terraform apply -var app_version=...` it prints. `app_version` has no default, so pass it on every apply (use the version currently deployed when changing other settings). The new `app_version` changes the launch template, so the ASG replaces instances one at a time without dropping capacity. A new Amazon Linux AMI also triggers a refresh on the next apply.

## Migrations

Each instance runs `node dist/migrate.js` in its boot script, before it starts the server. The database is in private subnets, so nothing outside the VPC can reach it, and running migrations from the instances avoids a separate migrate step (and a bastion or tunnel for it).

Consequences:

- Instances that boot together (first deploy with `asg_desired` > 1, a refresh that launches several at once) would race, so the migrator takes a Postgres advisory lock (`src/migrator.ts`). With the practice defaults (1 instance) there is no race; the lock matters at larger sizes.
- During a rollout the first new instance migrates while old instances still serve traffic, so every migration must work with both the old and the new code. Renames, drops and type changes need two releases (add, then remove later).
- A failing migration fails that instance's boot (after 5 tries), so the new instance never goes healthy and the refresh rolls back.

Alternative: run migrations once before the rollout (for example through SSM on one existing instance) and drop the step from `user_data.sh.tftpl`. The lock would then be unnecessary, but the first deploy still needs an instance to run it from, and the backward-compatibility rule stays.

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

## Cost (the figures below are on-demand `us-east-1` prices; other regions, including the default `eu-north-1`, differ. Check with the AWS Pricing Calculator)

Practice, always on: about $0.07/hour, about $52/month (NLB ~$0.039/h, t4g.micro ~$0.014/h, db.t4g.micro ~$0.019/h). At 10 hours a week with `terraform destroy` in between, a few dollars a month. Cost alerts are account-wide, so they are not part of this Terraform; set a budget once in the AWS console.

Full scale: about $4,000/month (data transfer out ~$2,660, RDS ~$630, servers ~$370, NLB ~$290, IPv4 ~$40). Don't send per-request logs to CloudWatch: ~200 GB/day would add ~$3,000/month.
