# Deploying to AWS

Runs the app on [Amazon ECS Express Mode](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-overview.html) with an RDS Postgres database. Practice uses the defaults in the `variables.tf` files; the `full-scale.tfvars.example` files show full-scale sizes (reference only).

```
Internet -> ALB (HTTPS) -> Fargate tasks (:3000, public subnets) -> RDS Postgres 16 (private subnets)
```

From the one service in `app/main.tf`, Express Mode creates the load balancer, HTTPS certificate, autoscaling and canary deployments ([what it creates](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-work.html)). Tasks get public IPs instead of a NAT gateway, and only the load balancer can reach them.

A push to `main` that changes the app is deployed by GitHub Actions. Why it is built this way is in [ADR 0003](../docs/decisions/0003-split-stacks-remote-state-and-ci-deploys.md).

## The three stacks

Terraform is split in three, each with its own state, so that the part that changes every release can't break the parts that must not change.

| Folder | What is in it | Who applies it |
| --- | --- | --- |
| `bootstrap/` | The S3 bucket for state, the GitHub sign-in (OIDC provider) and two IAM roles for CI | You, once, by hand |
| `foundation/` | The VPC, the database and its password, the security groups, the two roles ECS uses | You, from your machine, after reading `terraform plan` |
| `app/` | The ECR repository, the log group, the ECS Express service | GitHub Actions on push to `main`, or you with `scripts/release.sh` |

The state of `foundation/` and `app/` is in the S3 bucket. It holds no secrets: the database password is generated on each run and never stored ([ADR 0003](../docs/decisions/0003-split-stacks-remote-state-and-ci-deploys.md)). The state of `bootstrap/` stays on your machine (see "If you lose the bootstrap state").

CI uses two roles that only GitHub's own sign-in can assume. `github-plan-url-shortener` is read-only, is used on pull requests to plan the app stack, and is denied every secret. `github-deploy-url-shortener` can push images and update the one service, and only the `production` environment (the `main` branch) can use it. Neither can change IAM, the network or the database.

## Prerequisites

- Terraform via [tfenv](https://github.com/tfutils/tfenv): run `tfenv install` in the repo. It must be 1.11 or newer (the database password uses write-only arguments and an ephemeral resource).
- An AWS CLI profile that can create the resources (for the bootstrap and foundation steps, admin is simplest), Docker and git.
- Your account's region (AWS Settings > Project). The default is `eu-north-1`; to change it, put `region = "..."` in a `terraform.tfvars` in each stack folder.
- Everything used is on the AWS Free plan ([list](https://docs.aws.amazon.com/accounts/latest/reference/supported-services-sign-up-new.html)).

## Set up (once)

### 1. Apply the bootstrap

```bash
cd infra/bootstrap
terraform init
terraform apply
terraform output
```

This creates the state bucket (`url-shortener-tfstate-<account id>`), the OIDC provider and the two roles. Keep the outputs for steps 2 and 3.

If the account already has a GitHub OIDC provider (AWS allows one), the apply fails. Run it with `-var create_github_oidc_provider=false` to use the existing one.

### 2. Point the other stacks at the bucket

```bash
cd infra
cp backend.hcl.example backend.hcl    # put the bucket from `output state_bucket` in it
echo 'state_bucket = "<the same bucket>"' > app/terraform.tfvars
terraform -chdir=foundation init -backend-config=../backend.hcl
terraform -chdir=app init -backend-config=../backend.hcl
```

The app stack reads the foundation's state from the same bucket, so it needs the name too: that is `state_bucket` in `app/terraform.tfvars`. It has no default, so the stack never guesses the name. CI sets it from `TF_STATE_BUCKET`. Both files are gitignored (they name your account). The state is locked with a small file in the bucket while Terraform runs, so two runs can't collide.

### 3. Set up GitHub

In the repository, Settings > Environments, create an environment named `production`. Under "Deployment branches and tags" choose "Selected branches and tags" and add `main`. Without this, any branch could use the deploy role.

Then add these variables under Settings > Secrets and variables > Actions > Variables. None are secret.

| Variable | Value | Where |
| --- | --- | --- |
| `AWS_REGION` | `eu-north-1` | Repository |
| `TF_STATE_BUCKET` | `terraform output state_bucket`. The one place CI gets the bucket name from: it is used for the backend and as the app stack's `state_bucket` | Repository |
| `AWS_PLAN_ROLE_ARN` | `terraform output plan_role_arn` | Repository |
| `AWS_DEPLOY_ROLE_ARN` | `terraform output deploy_role_arn` | Environment `production` |

Until `AWS_PLAN_ROLE_ARN` is set, the pull request check skips the app plan and says so in its summary. The plan also needs the foundation to be applied: it reads the foundation's state file in the bucket, and says "skipped" if there are no outputs in it. Any other problem reading it (no access, wrong bucket) fails the check.

## First run

Do these in order, on a commit that is on `main`.

1. **Apply the foundation.** Read the plan first. It takes 10-15 minutes because it creates the database.

   ```bash
   terraform -chdir=infra/foundation apply
   ```

2. **Stand the app up from your machine**, because CI only updates a service that already exists.

   ```bash
   infra/scripts/release.sh
   curl $(terraform -chdir=infra/app output -raw url)/health   # {"status":"ok"}
   ```

   If it fails with "Unable to assume the service linked role", ECS has just created that role for the account: run `release.sh` again a minute later.

3. **Run the workflow once by hand.** In GitHub, Actions > Deploy > Run workflow, on `main`, with `app_version` empty. The image is already in ECR, so it skips the build and checks that CI can sign in and plan.

Two things can go wrong here, and both are expected:

- **"Not authorized to perform sts:AssumeRoleWithWebIdentity".** The roles trust a token whose `sub` is `repo:curiousdirection/url-shortener:environment:production` (and `...:pull_request` for the plan role). GitHub repositories created or renamed after 15 July 2026 send an ID-based `sub` instead, such as `repo:curiousdirection@<owner id>/url-shortener@<repo id>:environment:production` ([GitHub docs](https://docs.github.com/en/actions/reference/security/oidc)). Get the two ids with `gh api repos/curiousdirection/url-shortener --jq '.owner.id, .id'`, then run `terraform apply -var 'github_oidc_sub_prefix=repo:curiousdirection@<owner id>/url-shortener@<repo id>'` in `bootstrap/` and run the workflow again. (The form for the environment and pull request parts is not shown in GitHub's docs, so confirm it.)
- **"not authorized to perform ecs:..." (or `ecr:`, `logs:`).** The deploy role's permissions in `bootstrap/github.tf` were written from the AWS docs and have not been run against a real account. Add the action it names, apply the bootstrap and run again. Do the same for the plan role if the pull request plan fails.

Then merge a small app change and watch it go out by itself.

## Deploy

**Normal case.** Merge to `main`. If the change touches `src/`, `migrations/`, `package.json`, `package-lock.json`, `tsconfig.json`, `Dockerfile`, `.dockerignore`, `.node-version`, `.terraform-version`, `infra/app/`, or the workflow files that deploy (`deploy.yml`, `test.yml`, `.github/actions/setup-terraform/`), the workflow runs:

1. Tests, against a Postgres 16 service.
2. A check that the app is deployed. If the stack is torn down, the run ends green with "the app is not deployed" in its summary, and changes nothing.
3. Build the image for arm64, tagged with the first 7 characters of the commit SHA, and push it. Skipped if that tag is already in ECR.
4. `terraform plan`, then `terraform apply` of that saved plan. The apply waits for the release to go live (10-15 minutes).
5. `curl` on `/health`. The URL and the tag are in the run's summary.

Only one deploy runs at a time. A push during a deploy waits its turn.

**From your machine.** Commit, then run `infra/scripts/release.sh`. It does the same as the workflow, and asks you to confirm the apply. Each task runs the migrations before it starts ([ADR 0001](../docs/decisions/0001-run-migrations-on-every-instance.md)).

**Infrastructure changes** (anything in `bootstrap/` or `foundation/`). Pull requests don't plan these: refreshing the foundation would decrypt the database password, and any pull request can use the plan role. Check out the branch, read the plan, then merge and apply it yourself:

```bash
terraform -chdir=infra/foundation plan
terraform -chdir=infra/foundation apply
```

If an app change needs a foundation change, apply the foundation first. The app plan on the pull request fails or shows the gap. CI never applies `foundation/` or `bootstrap/`.

## Rotate the database password

The password is generated fresh on every run, but it is only written to AWS when the parameter is created or `db_password_version` changes. To set a new one, raise the version by one in `infra/foundation/terraform.tfvars` (or pass `-var db_password_version=2`) and apply the foundation. Terraform writes the new password to the parameter, then reads it back and updates the database with it, in the same apply.

The database never gets a password of its own: whenever it is written, it is given what the parameter holds. So the two can't differ, even if the parameter is deleted by hand or an apply stops half way. The next apply puts the database right. If you still suspect they differ (a run was killed at the wrong moment), raise the version again. The comments in `foundation/database.tf` list the cases.

Applying the foundation reads the parameter, so you need `ssm:GetParameter` and `kms:Decrypt` (admin has them). CI doesn't touch it.

**Running tasks keep the old password.** ECS hands a task the password once, when it starts. After a rotation, connections a task already holds keep working, but every new one fails, so the app returns errors until all tasks are replaced. Nothing rotates by itself; only raising `db_password_version` does this.

So pick one of these:

- **Rotate while the stack is torn down.** Nothing is running, so nothing breaks. (Recreating the stack also gives a new password.)
- **Rotate a running stack and accept a short outage** (usually 1-3 minutes). Do it at a quiet time:

  1. Apply the foundation with the new version, as above.
  2. Stop the running tasks straight away. The service starts new ones, which read the new password:

     ```bash
     for task in $(aws ecs list-tasks --region eu-north-1 --cluster default --service-name url-shortener --query 'taskArns[]' --output text); do
       aws ecs stop-task --region eu-north-1 --cluster default --task "$task" --reason "DB password rotated" >/dev/null
     done
     ```

  3. Wait until `curl $(terraform -chdir=infra/app output -raw url)/health` answers `{"status":"ok"}` again.

  Stopping the tasks is deliberate. A re-run of the Deploy workflow with the same image doesn't replace them, and a new release goes through the canary: the old tasks' errors can trip its alarm and roll the release back, which leaves the old tasks running.

Moving the app to IAM database authentication would remove this outage, because the app would no longer use the password ([ADR 0003](../docs/decisions/0003-split-stacks-remote-state-and-ci-deploys.md), "Alternatives").

## Rollback

A release first gets 5% of traffic and rolls back by itself if its error alarm fires; the apply step then fails and so does the run. The alarm adds the app's 4xx to its 5xx, ignoring fewer than 5 4xx in a check, and fires above 1% of requests ([docs](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-update-full.html)). A few stray 404s don't matter, but if more than 1% of real traffic is unknown codes or taken aliases, a good release rolls back.

To go back to an earlier release that was already live:

- In GitHub, Actions > Deploy > Run workflow, on `main`, with `app_version` set to the first 7 characters of the earlier commit SHA. It skips the tests and the build, and fails if that tag isn't in ECR.
- Or revert the commit on `main` and let the workflow ship the revert.
- Or from your machine: `terraform -chdir=infra/app apply -var app_version=<earlier commit>`.

ECR keeps the last 10 images. Migrations aren't rolled back, so each must work with the previous code too.

To stop deploying on push, delete `.github/workflows/deploy.yml`. The state stays in S3 and `release.sh` keeps working.

## Tear down

Take the app down before the foundation. The service uses the foundation's roles and security groups, and removing a role's policy before ECS is done with the service leaves it stuck in `DRAINING`.

```bash
terraform -chdir=infra/app destroy -var app_version=none
terraform -chdir=infra/foundation destroy
```

Express Mode removes what it created. While the app stack is empty, pushes to `main` end green with "the app is not deployed" and change nothing. To bring everything back, apply the foundation, then run `release.sh`.

The bootstrap stays. It costs almost nothing (an empty bucket and two roles). To remove it too, empty the bucket (versions included) and run `terraform destroy` in `infra/bootstrap`; the apply refuses to delete a bucket that still holds state.

Then check nothing is left; both should print nothing:

```bash
aws resourcegroupstaggingapi get-resources --region eu-north-1 --tag-filters Key=Project,Values=url-shortener --query 'ResourceTagMappingList[].ResourceARN' --output text
aws rds describe-db-snapshots --region eu-north-1 --snapshot-type manual --query 'DBSnapshots[].DBSnapshotIdentifier' --output text
```

The first still lists the state bucket (it is tagged `Project=url-shortener`) while the bootstrap exists, and can list deleted resources for a few hours; if `terraform state list` is empty in `app/` and `foundation/`, those are stale. The second lists manual snapshots; only `url-shortener-final-*` ones are from this stack (full-scale settings keep one; delete it with `aws rds delete-db-snapshot --db-snapshot-identifier <name>`). An empty `default` ECS cluster may stay behind; it's free.

## If you lose the bootstrap state

`bootstrap/terraform.tfstate` is only on your machine. It has no secrets, so losing it breaks nothing that runs. To manage the bootstrap again, run `terraform init` there and import what exists (`terraform import aws_s3_bucket.state <bucket>`, and the same for the other resources listed in `terraform plan`), until the plan shows no changes. Or move the state into the bucket as well: add a `backend "s3"` block with the key `bootstrap/terraform.tfstate` and run `terraform init -migrate-state`. Both roles are denied access to that key.

## Cost

On-demand `eu-north-1` (Stockholm) prices from the AWS Price List, November 2026.

- **Practice:** about $50/month if left running: load balancer ~$17, one small task ~$8, database ~$14 including 20 GB of storage, public IPv4 ~$11. Destroy between sessions and it's a few dollars a month. Set a budget alert in the AWS console.
- **Full scale:** about $6,200/month: data transfer out ~$2,650, load balancer ~$2,590 (it bills by new connections per second, and nearly every redirect is one), tasks ~$440, RDS ~$430 (Multi-AZ instance and 300 GB), IPv4 ~$40. An NLB with EC2 servers would cost roughly $2,100 less, for more parts to run ([ADR 0002](../docs/decisions/0002-deploy-with-ecs-express-mode.md)).

Don't send per-request logs to CloudWatch: ~200 GB/day would add ~$3,300/month.
