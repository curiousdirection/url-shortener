# Deploying to AWS

Terraform for the app on [Amazon ECS Express Mode](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-overview.html), plus a VPC and an RDS Postgres database. The same Terraform serves practice and full scale; only variable values differ (the defaults in `variables.tf` vs `full-scale.tfvars.example`).

```
Internet -> ALB (HTTPS) -> Fargate tasks (:3000, 2 public subnets) -> RDS Postgres 16 (private subnets)
```

- **Express Mode:** from an image and two IAM roles it creates the ECS service, the ALB with its HTTPS certificate and a `*.on.aws` address, health checks, canary deployments and CPU autoscaling ([what it creates](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-work.html)). The rest of `app.tf` is the image repository, the two roles and a security group.
- **ALB, not NLB:** Express Mode only builds ALBs. At full scale that costs more (see Cost).
- **No NAT gateway, no SSH:** tasks sit in public subnets with a public IP, and only the load balancer can reach them.
- **Community module:** the network (VPC, subnets, route tables) uses [terraform-aws-modules/vpc](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws), the way most teams do. Everything else is written by hand so each piece is visible.
- **Local state:** it contains the DB password, so it is gitignored. A remote backend is a follow-up.

## Prerequisites

- [tfenv](https://github.com/tfutils/tfenv): run `tfenv install` once in the repo; it installs the pinned version from `.terraform-version`.
- An AWS CLI profile that can create the resources (`export AWS_PROFILE=...`).
- Docker and git, for `scripts/release.sh`.
- The default region is `eu-north-1`. A project account is fixed to the region AWS assigned it, so check AWS Settings > Project.
- The AWS Free plan includes every service used here ([list](https://docs.aws.amazon.com/accounts/latest/reference/supported-services-sign-up-new.html)).

## Deploy

Commit your changes, then:

```bash
cd infra
terraform init
./scripts/release.sh
```

The defaults in `variables.tf` are the practice sizes. To change a setting such as `region`, put it in `infra/terraform.tfvars` (gitignored) or pass `-var`.

`release.sh` tags the image with the git short SHA, so it refuses to run with uncommitted changes. On the first release it creates the image repository (the service needs an image, so the repository has to exist first). It then builds and pushes the image, and runs `terraform apply -var app_version=<sha>` for you to confirm. A release takes roughly 10 to 15 minutes, because `terraform apply` waits for the canary deployment to finish and fails if the deployment does. The first run takes about 15 to 25 minutes, because it also creates the database. Check the app is up; this should print `{"status":"ok"}`:

```bash
curl $(terraform output -raw url)/health
```

For any later change, code or settings, run `./scripts/release.sh` again. It deploys your current commit with your current settings (`terraform.tfvars` is gitignored, so editing it doesn't count as an uncommitted change).

Tasks run the migrations on startup, so a release is one step; see [docs/decisions/0001](../docs/decisions/0001-run-migrations-on-every-instance.md).

## Rollback

Express Mode deploys a canary: it starts the new tasks beside the old ones, checks their health, sends them 5% of traffic, and rolls back by itself if an alarm it manages goes off. The old tasks keep serving throughout, and `terraform apply` fails with the deployment's error. The alarm counts 4xx as well as 5xx responses ([docs](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-update-full.html)) and cannot be changed through the Express Mode API or Terraform, so a burst of normal 4xx (unknown codes, taken aliases) during a canary could roll back a healthy release. After a failed deploy, or to go back to an older release, apply the last good tag:

```bash
terraform apply -var app_version=<last good sha>
```

The last 10 images are kept in ECR. A migration that already ran stays applied, so it must work with the old code too.

## Tear down

```bash
terraform destroy -var app_version=none
```

Nothing is deployed on the way down, so any `app_version` works. The images go with the repository. Express Mode deletes what it created (the ALB, target group, certificate, its security groups, autoscaling and alarms), and Terraform deletes everything else.

After a destroy, check that nothing is left. Both commands should print nothing:

```bash
aws resourcegroupstaggingapi get-resources --region eu-north-1 --tag-filters Key=Project,Values=url-shortener --query 'ResourceTagMappingList[].ResourceARN' --output text
aws rds describe-db-snapshots --region eu-north-1 --snapshot-type manual --query 'DBSnapshots[].DBSnapshotIdentifier' --output text
```

The first lists anything tagged for this project. It updates slowly and can show deleted resources for a few hours: if `terraform state list` prints nothing and a direct lookup (e.g. `aws rds describe-db-instances --region eu-north-1 --db-instance-identifier url-shortener`, or `aws elbv2 describe-load-balancers --region eu-north-1` for the load balancer) returns not found, those ARNs are stale and cost nothing. The second lists every manual snapshot in the account; only `url-shortener-final-*` ones come from this stack, and keep costing money. The practice defaults skip the final snapshot and turn off deletion protection, so there should be none; full-scale values do the opposite, so there the second command will show the final snapshot until you delete it with `aws rds delete-db-snapshot --db-snapshot-identifier <name>`.

If Express Mode left something in the VPC (a security group or network interface), the VPC delete fails and says so.

Express Mode puts the service in the account's `default` ECS cluster, creating it if needed. The docs list the cluster among the things that may be deleted with the service; if `aws ecs list-clusters --region eu-north-1` still shows it, it is empty and free.

## Cost

The figures below are on-demand `us-east-1` prices; other regions, including the default `eu-north-1`, differ. Check with the AWS Pricing Calculator. They come from the AWS Price List files for ECS/Fargate, Elastic Load Balancing and RDS published 2026-11-11 to 2026-11-12.

Practice, always on: about $0.063/hour, about $46/month, plus database storage: the ALB $0.0225/hour, one 0.25 vCPU / 0.5 GB Graviton task $0.0099/hour, three public IPv4 addresses (two on the ALB, one on the task) $0.015/hour, and the database. At 10 hours a week with `terraform destroy` in between, a few dollars a month. A NAT gateway would add about $33/month, so there is none. Cost alerts are account-wide, so they are not part of this Terraform; set a budget once in the AWS console.

In `eu-north-1`, the default region, the database alone is about $0.02/hour (roughly $14/month): `db.t4g.micro` Single-AZ at $0.016/hour plus 20 GB of gp3 at $0.12 per GB-month. These figures come from the AWS Price List published 2026-11-12.

Full scale: about $6,500/month. Data transfer out ~$2,660, the ALB ~$2,730, RDS ~$630, Fargate tasks ~$400, IPv4 ~$40.

- **ALB:** $16 for the hours, plus ~$2,710 for capacity units: ~11,600 new connections/s on average, at 25 new connections/s per unit, is 464 units at $0.008 per unit-hour. New connections are the dimension that dominates here.
- **Tasks:** 7 tasks of 2 vCPU / 4 GB on Graviton (the ~7 `c7g.large` servers the load needs), $0.079/hour each.
- **Data transfer out, RDS and IPv4** are estimates that do not depend on the load balancer. Traffic between the ALB and tasks in other zones is not billed.

An NLB with EC2 servers would cost about $2,100/month less at full scale; that is the known trade-off for fewer parts to run (why we accepted that: [ADR 0002](../docs/decisions/0002-deploy-with-ecs-express-mode.md)).

Don't send per-request logs to CloudWatch: ~200 GB/day would add ~$3,000/month.
