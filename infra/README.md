# Deploying to AWS

Runs the app on [Amazon ECS Express Mode](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-overview.html) with an RDS Postgres database. Practice uses the defaults in `variables.tf`; `full-scale.tfvars.example` shows full-scale sizes (reference only).

```
Internet -> ALB (HTTPS) -> Fargate tasks (:3000, public subnets) -> RDS Postgres 16 (private subnets)
```

From the one service in `app.tf`, Express Mode creates the load balancer, HTTPS certificate, autoscaling and canary deployments ([what it creates](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-work.html)). Tasks get public IPs instead of a NAT gateway, and only the load balancer can reach them. The Terraform state holds the database password, so it stays local and gitignored.

## Prerequisites

- Terraform via [tfenv](https://github.com/tfutils/tfenv): run `tfenv install` in the repo.
- An AWS CLI profile that can create the resources, Docker and git.
- Your account's region (AWS Settings > Project). The default is `eu-north-1`; to change it, put `region = "..."` in `infra/terraform.tfvars`.
- Everything used is on the AWS Free plan ([list](https://docs.aws.amazon.com/accounts/latest/reference/supported-services-sign-up-new.html)).

## Deploy

Commit, then:

```bash
cd infra
terraform init
./scripts/release.sh
```

`release.sh` builds the image, tags it with the commit, pushes it and runs `terraform apply` for you to confirm. The first run takes 15–25 minutes because it creates the database; later ones 10–15, because the apply waits for the release to go live. Then check:

```bash
curl $(terraform output -raw url)/health   # {"status":"ok"}
```

Run `release.sh` again for any later change, code or settings. Each task runs the migrations before it starts ([ADR 0001](../docs/decisions/0001-run-migrations-on-every-instance.md)).

If the first deploy fails with "Unable to assume the service linked role", ECS has just created that role for the account: run `release.sh` again a minute later.

## Alerts

Put `alarm_email = "you@example.com"` in `infra/terraform.tfvars` and run `release.sh`; then click the link in AWS's confirmation email. Three alarms email you (and again when they clear):

- the app answers more than 5% of requests with a 5xx for 10 minutes;
- the load balancer answers 5xx itself, usually because no task is healthy;
- the database has less than 10% of its disk free.

App logs (startup, migrations, errors) are in CloudWatch Logs under `/url-shortener/app` for 7 days.

## Rollback

A release first gets 5% of traffic and rolls back by itself if its error alarm fires; `terraform apply` then fails. The alarm counts 4xx as well as 5xx ([docs](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-update-full.html)), so normal 404s could roll back a good release. To go back to an earlier release:

```bash
terraform apply -var app_version=<earlier commit sha>
```

ECR keeps the last 10 images. Migrations aren't rolled back, so each must work with the previous code too.

## Tear down

```bash
terraform destroy -var app_version=none
```

Express Mode removes what it created. Then check nothing is left; both should print nothing:

```bash
aws resourcegroupstaggingapi get-resources --region eu-north-1 --tag-filters Key=Project,Values=url-shortener --query 'ResourceTagMappingList[].ResourceARN' --output text
aws rds describe-db-snapshots --region eu-north-1 --snapshot-type manual --query 'DBSnapshots[].DBSnapshotIdentifier' --output text
```

The first can still list deleted resources for a few hours; if `terraform state list` is empty, they're stale. The second lists manual snapshots; only `url-shortener-final-*` ones are from this stack (full-scale settings keep one; delete it with `aws rds delete-db-snapshot --db-snapshot-identifier <name>`). An empty `default` ECS cluster may stay behind; it's free.

## Cost

On-demand `eu-north-1` (Stockholm) prices from the AWS Price List, November 2026.

- **Practice:** about $50/month if left running: load balancer ~$17, one small task ~$8, database ~$14 including 20 GB of storage, public IPv4 ~$11. Destroy between sessions and it's a few dollars a month. Alarms add about $0.40. Set a budget alert in the AWS console.
- **Full scale:** about $6,200/month: data transfer out ~$2,650, load balancer ~$2,590 (it bills by new connections per second, and nearly every redirect is one), tasks ~$440, RDS ~$430 (Multi-AZ instance and 300 GB), IPv4 ~$40. An NLB with EC2 servers would cost roughly $2,100 less, for more parts to run ([ADR 0002](../docs/decisions/0002-deploy-with-ecs-express-mode.md)).

Don't send per-request logs to CloudWatch: ~200 GB/day would add ~$3,300/month.
