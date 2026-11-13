# Deploying to AWS

Terraform for a practice deployment that has the same structure as the full-scale design, so only variable values differ (`terraform.tfvars.example` vs `full-scale.tfvars.example`).

```
Internet -> NLB (2 public subnets) -> Auto Scaling group of EC2 (:3000) -> RDS Postgres 16 (private subnets)
```

- **NLB, not ALB:** at ~11,600 new connections/s, ALB capacity units would cost ~$2,700/month against ~$290 for the NLB.
- **No NAT gateway, no API Gateway, no Lambda:** instances sit in public subnets with a public IP and accept only the NLB's security group.
- **No SSH:** use SSM Session Manager.
- **Community module:** the network (VPC, subnets, route tables) uses [terraform-aws-modules/vpc](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws), the way most teams do. Everything else is written by hand so each piece is visible. Run `terraform init` after pulling to download the module.
- **Local state:** it contains the DB password, so it is gitignored. A remote backend is a follow-up.

## Prerequisites

- [tfenv](https://github.com/tfutils/tfenv): run `tfenv install` once in the repo; it installs the pinned version from `.terraform-version`.
- An AWS CLI profile that can create the resources (`export AWS_PROFILE=...`).
- Node and git, for `scripts/release.sh`.
- The default region is `eu-north-1`. A project account is fixed to the region AWS assigned it, so check AWS Settings > Project.

## First deploy

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # optional: adjust sizes and region
terraform init
terraform apply -target=aws_s3_bucket.releases -var app_version=none   # the bucket must exist before the first release
./scripts/release.sh                             # prints the release version
terraform apply -var app_version=<that version>
```

Then:

```bash
curl http://$(terraform output -raw nlb_dns_name)/health
```

The first apply waits up to 10 minutes for the targets to become healthy. If it times out, open a session with `aws ssm start-session --target <instance-id>` and read `/var/log/user-data.log`.

## Releasing

Commit, run `infra/scripts/release.sh` (from any directory), then in `infra/` run `terraform apply -var app_version=<the version it printed>`. `app_version` has no default, so pass it on every apply (use the version currently deployed when changing other settings). The new `app_version` changes the launch template, so the ASG replaces instances one at a time without dropping capacity. A new Amazon Linux AMI also triggers a refresh on the next apply.

`terraform apply` does not wait for the rolling replacement to finish, so a successful apply does not mean the release is healthy. Watch it with:

```bash
aws autoscaling describe-instance-refreshes --auto-scaling-group-name $(terraform output -raw asg_name)
```

If the new version never gets healthy, `auto_rollback` puts the group back on the previous launch template version. Terraform still has the new version in its state, so the next `apply` would start the same broken refresh again. Re-apply with the last good `app_version` instead.

## Migrations

Each instance runs `node dist/migrate.js` in its boot script, before it starts the server. The database is in private subnets, so nothing outside the VPC can reach it, and running migrations from the instances avoids a separate migrate step (and a bastion or tunnel for it).

Consequences:

- Instances that boot together (first deploy with `asg_desired` > 1, a refresh that launches several at once) would race, so the migrator takes a Postgres advisory lock (`src/migrator.ts`). With the practice defaults (1 instance) there is no race; the lock matters at larger sizes.
- During a rollout the first new instance migrates while old instances still serve traffic, so every migration must work with both the old and the new code. Renames, drops and type changes need two releases (add, then remove later).
- A failing migration fails that instance's boot (after 5 tries), so the new instance never goes healthy and the refresh rolls back (see "Releasing" for what to do next).

Alternative: run migrations once before the rollout (for example through SSM on one existing instance) and drop the step from `user_data.sh.tftpl`. The lock would then be unnecessary, but the first deploy still needs an instance to run it from, and the backward-compatibility rule stays.

## Known limitations

- **Every boot downloads Node from nodejs.org and runs `npm ci` against the npm registry.** If either is slow or down, new instances (including scale-out) fail their health checks and get replaced in a loop, and `npm ci` on a `t4g.micro` uses part of the 300 s grace period. A fix is to ship production `node_modules` in the release tarball and host the Node tarball in the release bucket or bake an AMI.
- **`/health` doesn't check the database,** so an instance that has lost its database connection stays in service. Checking it has a cost too: a database blip would make every instance unhealthy at once.
- **`terraform apply` doesn't wait for a release to finish rolling out** (see "Releasing").

## Scaling

`asg_desired` only sets the initial size; the ASG ignores later changes so autoscaling (target 60% CPU) and manual scaling are not undone:

```bash
aws autoscaling set-desired-capacity --auto-scaling-group-name <name> --desired-capacity 2
```

## Tear down

```bash
terraform destroy -var app_version=none
```

`app_version` has no default, so destroy asks for it too (or fails when not interactive). Nothing is deployed on the way down, so any value works.

After a destroy, check that nothing is left. Both commands should print nothing:

```bash
aws resourcegroupstaggingapi get-resources --region eu-north-1 --tag-filters Key=Project,Values=url-shortener --query 'ResourceTagMappingList[].ResourceARN' --output text
aws rds describe-db-snapshots --region eu-north-1 --snapshot-type manual --query 'DBSnapshots[].DBSnapshotIdentifier' --output text
```

The first lists anything tagged for this project (servers, load balancer, the release bucket, the database). It updates slowly and can show deleted resources for a few hours: if `terraform state list` prints nothing and a direct lookup (e.g. `aws rds describe-db-instances --region eu-north-1 --db-instance-identifier url-shortener`, or `aws elbv2 describe-load-balancers --region eu-north-1 --names url-shortener` for the load balancer) returns not found, those ARNs are stale and cost nothing. The second lists every manual snapshot in the account; only `url-shortener-final-*` ones come from this stack, and keep costing money. The practice defaults skip the final snapshot and turn off deletion protection, so there should be none; full-scale values do the opposite, so there the second command will show the final snapshot until you delete it with `aws rds delete-db-snapshot --db-snapshot-identifier <name>`.

## Cost (the figures below are on-demand `us-east-1` prices; other regions, including the default `eu-north-1`, differ. Check with the AWS Pricing Calculator)

Practice, always on: about $0.07/hour, about $52/month (NLB ~$0.039/h, t4g.micro ~$0.014/h, db.t4g.micro ~$0.019/h). At 10 hours a week with `terraform destroy` in between, a few dollars a month. Cost alerts are account-wide, so they are not part of this Terraform; set a budget once in the AWS console.

In `eu-north-1`, the default region, the database alone is about $0.02/hour (roughly $14/month): `db.t4g.micro` Single-AZ at $0.016/hour plus 20 GB of gp3 at $0.12 per GB-month. These figures come from the AWS Price List published 2026-11-12.

Full scale: about $4,300/month (data transfer out ~$2,660, RDS ~$630, servers ~$370, NLB ~$290, cross-zone traffic ~$300, IPv4 ~$40).

Cross-zone traffic is an estimate: with 2 AZs about half of the ~30 TB/month of responses crosses AZs, at $0.02/GB (inter-AZ, both ends). Don't send per-request logs to CloudWatch: ~200 GB/day would add ~$3,000/month.
