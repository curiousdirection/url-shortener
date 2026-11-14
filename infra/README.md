# Deploying to AWS

Runs the app on [Amazon ECS Express Mode](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-overview.html) with an Aurora PostgreSQL database. Practice uses the defaults in `variables.tf`; `full-scale.tfvars.example` shows full-scale sizes (reference only).

```
Internet -> ALB (HTTPS) -> Fargate tasks (:3000, public subnets) -> Aurora PostgreSQL 16 (private subnets)
```

From the one service in `app.tf`, Express Mode creates the load balancer, HTTPS certificate, autoscaling and canary deployments ([what it creates](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-work.html)). Tasks get public IPs instead of a NAT gateway, and only the load balancer can reach them. The practice database pauses when idle ([ADR 0003](../docs/decisions/0003-aurora-postgresql-at-both-scales.md)). The Terraform state holds the database password, so it stays local and gitignored.

## Prerequisites

- Terraform via [tfenv](https://github.com/tfutils/tfenv): run `tfenv install` in the repo.
- An AWS CLI profile that can create the resources, Docker and git.
- Your account's region (AWS Settings > Project). The default is `eu-north-1`; to change it, put `region = "..."` in `infra/terraform.tfvars`.
- The Paid plan. On the Free plan, Aurora only works for clusters made with the console's "express configuration" ([docs](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-free-tier.html)), which Terraform doesn't use. Free Tier credits still apply on the Paid plan.

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

## Look at the data

The database has no public address, so use the RDS Data API, which runs SQL over HTTPS. Your IAM user needs the `AmazonRDSDataFullAccess` policy.

In the console: RDS > Databases > the `url-shortener` cluster > Actions > Query. Connect with user `urlshortener`, database `urlshortener` and the password from Secrets Manager (secret `rds-db-credentials/url-shortener` > Retrieve secret value). Then run `SELECT * FROM urls;`. The console saves the login as a secret of its own.

From the command line, with the secret Terraform made:

```bash
aws rds-data execute-statement --region eu-north-1 \
  --resource-arn "$(terraform output -raw db_cluster_arn)" \
  --secret-arn "$(terraform output -raw db_secret_arn)" \
  --database urlshortener --sql 'SELECT * FROM urls'
```

A query resumes a paused database, so the first one can take about 15 seconds.

## Rollback

A release first gets 5% of traffic and rolls back by itself if its error alarm fires; `terraform apply` then fails. The alarm adds the app's 4xx to its 5xx, ignoring fewer than 5 4xx in a check, and fires above 1% of requests ([docs](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-update-full.html)). A few stray 404s don't matter, but if more than 1% of real traffic is unknown codes or taken aliases, a good release rolls back. To go back to an earlier release:

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
aws rds describe-db-cluster-snapshots --region eu-north-1 --snapshot-type manual --query 'DBClusterSnapshots[].DBClusterSnapshotIdentifier' --output text
```

The first can still list deleted resources for a few hours; if `terraform state list` is empty, they're stale. The second lists manual cluster snapshots; only `url-shortener-final-*` ones are from this stack (full-scale settings keep one; delete it with `aws rds delete-db-cluster-snapshot --db-cluster-snapshot-identifier <name>`). An empty `default` ECS cluster may stay behind; it's free.

## Cost

On-demand `eu-north-1` (Stockholm) prices from the AWS Price List, November 2026.

- **Practice:** about $40/month if left running: load balancer ~$17, one small task ~$8, public IPv4 ~$11, database ~$1–5 while mostly idle. The database pauses after 5 idle minutes and then costs only storage ($0.11 per GB-month) and the secret (~$0.40/month). While running, compute is $0.14 per ACU-hour: ~$51/month for each 0.5 ACU it stays on, ~$204 at the 2 ACU cap. Queries through the Data API are free for the first million requests a month in the first year, then billed per request. Destroy between sessions and it's a few dollars a month. Set a budget alert in the AWS console.
- **Full scale:** about $6,200/month: data transfer out ~$2,650, load balancer ~$2,590 (it bills by new connections per second, and nearly every redirect is one), tasks ~$440, Aurora ~$450 (two `db.r7g.large` at $0.285/hour and 300 GB), IPv4 ~$40, plus Aurora's I/O charges at $0.21 per million (I/O-Optimized instead costs $0.371/hour per instance, about $620/month for the database, with no I/O charges). The RDS Multi-AZ instance it replaced was ~$430. An NLB with EC2 servers would cost roughly $2,100 less, for more parts to run ([ADR 0002](../docs/decisions/0002-deploy-with-ecs-express-mode.md)).

Don't send per-request logs to CloudWatch: ~200 GB/day would add ~$3,300/month.
