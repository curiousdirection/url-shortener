# Deploying to AWS

Runs the app on [Amazon ECS Express Mode](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-overview.html) with an RDS Postgres database. Practice uses the defaults in the `variables.tf` files; the `full-scale.tfvars.example` files show full-scale sizes (reference only).

```
Internet -> ALB (HTTPS) -> Fargate tasks (:3000, public subnets) -> RDS Postgres 16 (private subnets)
```

From the one service in `app/main.tf`, Express Mode creates the load balancer, HTTPS certificate, autoscaling and canary deployments ([what it creates](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-work.html)). Tasks get public IPs instead of a NAT gateway, and only the load balancer can reach them.

A push to `main` that changes the app is deployed by GitHub Actions. Why it is built this way is in [ADR 0003](../docs/decisions/0003-split-stacks-remote-state-and-ci-deploys.md).

## The three stacks

| Folder | What is in it | Who applies it |
| --- | --- | --- |
| `bootstrap/` | The S3 state bucket, GitHub's sign-in (OIDC) and the two CI roles | You, once |
| `foundation/` | The VPC, the database and its password, security groups, the ECS roles | You, from your machine |
| `app/` | ECR, the log group, the ECS Express service | GitHub Actions on push to `main`, or you with `scripts/release.sh` |

The `foundation/` and `app/` state is in S3 and holds no secrets. The `bootstrap/` state stays on your machine.

## Prerequisites

- Terraform via [tfenv](https://github.com/tfutils/tfenv): run `tfenv install` in the repo (1.11 or newer).
- An AWS CLI profile that can create the resources (admin is simplest), Docker and git.
- Your account's region (AWS Settings > Project). The default is `eu-north-1`; to change it, put `region = "..."` in a `terraform.tfvars` in each stack folder.
- Everything used is on the AWS Free plan ([list](https://docs.aws.amazon.com/accounts/latest/reference/supported-services-sign-up-new.html)).

## Set up and first run

Do these once, in order, on a commit that is on `main`.

1. **Apply the bootstrap.** If the account already has a GitHub OIDC provider, add `-var create_github_oidc_provider=false`.

   ```bash
   terraform -chdir=infra/bootstrap init
   terraform -chdir=infra/bootstrap apply
   terraform -chdir=infra/bootstrap output
   ```

2. **Point the other stacks at the bucket.** Put the `state_bucket` output in `infra/backend.hcl` (copy `backend.hcl.example`) and in `infra/app/terraform.tfvars` as `state_bucket = "..."`. Both files are gitignored.

   ```bash
   terraform -chdir=infra/foundation init -backend-config=../backend.hcl
   terraform -chdir=infra/app init -backend-config=../backend.hcl
   ```

3. **Set up GitHub.** Under Settings > Environments, create `production` and limit its deployment branches to `main`. Then add these variables (none are secret) under Settings > Secrets and variables > Actions:

   | Variable | Value | Where |
   | --- | --- | --- |
   | `AWS_REGION` | `eu-north-1` | Repository |
   | `TF_STATE_BUCKET` | `state_bucket` output | Repository |
   | `AWS_PLAN_ROLE_ARN` | `plan_role_arn` output | Repository |
   | `AWS_DEPLOY_ROLE_ARN` | `deploy_role_arn` output | Environment `production` |

4. **Apply the foundation.** Read the plan first. It takes 10-15 minutes because it creates the database.

   ```bash
   terraform -chdir=infra/foundation apply
   ```

5. **Stand the app up from your machine**, because CI only updates a service that already exists.

   ```bash
   infra/scripts/release.sh
   curl $(terraform -chdir=infra/app output -raw url)/health   # {"status":"ok"}
   ```

   If it fails with "Unable to assume the service linked role", ECS has just created that role for the account: run `release.sh` again a minute later.

6. **Run the Deploy workflow once by hand** (Actions > Deploy > Run workflow, on `main`, `app_version` empty) to check that CI can sign in and plan.

If CI can't sign in ("Not authorized to perform sts:AssumeRoleWithWebIdentity"), the repository probably sends GitHub's ID-based `sub` claim (repositories created or renamed after 15 July 2026, [docs](https://docs.github.com/en/actions/reference/security/oidc)). Get the ids with `gh api repos/curiousdirection/url-shortener --jq '.owner.id, .id'` and apply the bootstrap with `-var 'github_oidc_sub_prefix=repo:curiousdirection@<owner id>/url-shortener@<repo id>'`. If a role is refused an `ecs:`, `ecr:` or `logs:` action, add it in `bootstrap/github.tf` and apply the bootstrap again: the permission lists haven't been run against a real account yet.

## Deploy

**Normal case.** Merge to `main`. A change to the app, its build files or `infra/app/` (the full list is under `paths` in `.github/workflows/deploy.yml`) runs the tests, builds and pushes the image (tagged with the first 7 characters of the commit SHA), applies the app stack and checks `/health`. One deploy runs at a time. If the stack is torn down, the run ends green and changes nothing.

**From your machine.** Commit, then run `infra/scripts/release.sh`. It does the same, and asks you to confirm the apply. Each task runs the migrations before it starts ([ADR 0001](../docs/decisions/0001-run-migrations-on-every-instance.md)).

**Infrastructure changes** (`bootstrap/` or `foundation/`). CI never plans or applies these. Read the plan, then merge and apply it yourself, before any app change that needs it:

```bash
terraform -chdir=infra/foundation plan
terraform -chdir=infra/foundation apply
```

## Rotate the database password

Raise `db_password_version` by one in `infra/foundation/terraform.tfvars` and apply the foundation. The parameter and the database get the new password in the same apply.

Running tasks keep the old password, so every new connection fails until they are replaced. Either rotate while the stack is torn down, or do it at a quiet time and stop the tasks straight after (expect 1-3 minutes of errors):

```bash
for task in $(aws ecs list-tasks --region eu-north-1 --cluster default --service-name url-shortener --query 'taskArns[]' --output text); do
  aws ecs stop-task --region eu-north-1 --cluster default --task "$task" --reason "DB password rotated" >/dev/null
done
```

Don't use a new release for this: the old tasks' errors can trip the canary's alarm and roll it back.

## Rollback

A release first gets 5% of traffic and rolls back by itself if its error alarm fires; the apply step then fails and so does the run. The alarm adds the app's 4xx to its 5xx, ignoring fewer than 5 4xx in a check, and fires above 1% of requests ([docs](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-update-full.html)). A few stray 404s don't matter, but if more than 1% of real traffic is unknown codes or taken aliases, a good release rolls back.

To go back to an earlier release, run the Deploy workflow by hand with `app_version` set to the earlier commit's first 7 characters (it skips the tests and the build), or revert the commit on `main`.

ECR keeps the last 10 images. Migrations aren't rolled back, so each must work with the previous code too.

## Tear down

App first, then the foundation (the service uses the foundation's roles):

```bash
terraform -chdir=infra/app destroy -var app_version=none
terraform -chdir=infra/foundation destroy
```

Express Mode removes what it created. The bootstrap stays; it costs almost nothing. To remove it too, empty the bucket (versions included) and run `terraform destroy` in `infra/bootstrap`.

Then check nothing is left; both should print nothing:

```bash
aws resourcegroupstaggingapi get-resources --region eu-north-1 --tag-filters Key=Project,Values=url-shortener --query 'ResourceTagMappingList[].ResourceARN' --output text
aws rds describe-db-snapshots --region eu-north-1 --snapshot-type manual --query 'DBSnapshots[].DBSnapshotIdentifier' --output text
```

The first lists the state bucket while the bootstrap exists, and can list deleted resources for a few hours; if `terraform state list` is empty in `app/` and `foundation/`, they're stale. The second lists manual snapshots; only `url-shortener-final-*` ones are from this stack (full-scale settings keep one; delete it with `aws rds delete-db-snapshot --db-snapshot-identifier <name>`). An empty `default` ECS cluster may stay behind; it's free.

## If you lose the bootstrap state

It has no secrets, so nothing that runs breaks. Run `terraform init` in `infra/bootstrap` and `terraform import` each resource `terraform plan` wants to create, until the plan shows no changes.

## Cost

On-demand `eu-north-1` (Stockholm) prices from the AWS Price List, November 2026.

- **Practice:** about $50/month if left running: load balancer ~$17, one small task ~$8, database ~$14 including 20 GB of storage, public IPv4 ~$11. Destroy between sessions and it's a few dollars a month. Set a budget alert in the AWS console.
- **Full scale:** about $6,200/month: data transfer out ~$2,650, load balancer ~$2,590 (it bills by new connections per second, and nearly every redirect is one), tasks ~$440, RDS ~$430 (Multi-AZ instance and 300 GB), IPv4 ~$40. An NLB with EC2 servers would cost roughly $2,100 less, for more parts to run ([ADR 0002](../docs/decisions/0002-deploy-with-ecs-express-mode.md)).

Don't send per-request logs to CloudWatch: ~200 GB/day would add ~$3,300/month.
