# Deploying to AWS

Runs the app as one [AWS Lambda](https://docs.aws.amazon.com/lambda/latest/dg/welcome.html) function with a function URL, and keeps the links in a DynamoDB table. Why: [ADR 0006](../docs/decisions/0006-move-to-lambda-and-dynamodb.md). Practice uses the defaults in the `variables.tf` files; the `full-scale.tfvars.example` files show full-scale settings (reference only).

```
Internet -> function URL (HTTPS) -> Lambda function -> DynamoDB table
```

A push to `main` that changes the app is deployed by GitHub Actions. Why it is built this way: [ADR 0003](../docs/decisions/0003-split-stacks-remote-state-and-ci-deploys.md).

## The three stacks

| Folder | What is in it | Who applies it |
| --- | --- | --- |
| `bootstrap/` | The S3 state bucket, the two CI roles and the IAM user that signs in as each | You, once (and again when its permissions change) |
| `foundation/` | The DynamoDB table and the function's IAM role | You, from your machine |
| `app/` | The Lambda function, its function URL, its log group | GitHub Actions on push to `main`, or you with `scripts/release.sh` |

All three states are in the S3 bucket.

## Prerequisites

- Terraform via [tfenv](https://github.com/tfutils/tfenv): run `tfenv install` in the repo (1.11 or newer).
- Node.js at the version in `.node-version` (the zip is built on your machine for `release.sh`), `zip` and `openssl`.
- An AWS CLI profile that can create the resources (admin is simplest), and git.
- Your account's region (AWS Settings > Project). The default is `eu-north-1`; to change it, put `region = "..."` in a `terraform.tfvars` in each stack folder.
- Everything used is allowed on the AWS Free plan ([list](https://docs.aws.amazon.com/accounts/latest/reference/supported-services-sign-up-new.html)).

## Set up and first run

Do these once, in order, on a commit that is on `main`.

1. **Apply the bootstrap.** Its state bucket doesn't exist yet, so this first apply keeps the state locally, through a gitignored override file.

   ```bash
   printf 'terraform {\n  backend "local" {}\n}\n' > infra/bootstrap/backend_override.tf
   terraform -chdir=infra/bootstrap init
   terraform -chdir=infra/bootstrap apply
   terraform -chdir=infra/bootstrap output
   ```

2. **Move the state into the bucket.** Put the `state_bucket` output in `infra/backend.hcl` (`cp infra/backend.hcl.example infra/backend.hcl`) and in `infra/app/terraform.tfvars` (touch `infra/app/terraform.tfvars`) as `state_bucket = "..."`. Both files are gitignored.

   ```bash
   rm infra/bootstrap/backend_override.tf
   terraform -chdir=infra/bootstrap init -migrate-state -backend-config=../backend.hcl # yes
   rm -f infra/bootstrap/terraform.tfstate infra/bootstrap/terraform.tfstate.backup
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

4. **Create the CI access keys.** The bootstrap made one IAM user per role but no keys, so they stay out of the state. Make each key and store it as a GitHub secret (`gh` and `jq` are used here; the secrets can also be added in Settings). The deploy keys go to the `production` environment from step 3, so only `main` can use them; the plan keys go to the repository.

   ```bash
   user=$(terraform -chdir=infra/bootstrap output -raw deploy_user_name)
   key=$(aws iam create-access-key --user-name "$user" --query AccessKey --output json)
   jq -j .AccessKeyId <<<"$key" | gh secret set AWS_DEPLOY_ACCESS_KEY_ID --env production
   jq -j .SecretAccessKey <<<"$key" | gh secret set AWS_DEPLOY_SECRET_ACCESS_KEY --env production

   user=$(terraform -chdir=infra/bootstrap output -raw plan_user_name)
   key=$(aws iam create-access-key --user-name "$user" --query AccessKey --output json)
   jq -j .AccessKeyId <<<"$key" | gh secret set AWS_PLAN_ACCESS_KEY_ID
   jq -j .SecretAccessKey <<<"$key" | gh secret set AWS_PLAN_SECRET_ACCESS_KEY
   unset key
   ```

5. **Apply the foundation.** Read the plan first. It takes a few seconds.

   ```bash
   terraform -chdir=infra/foundation apply
   ```

6. **Create the function from your machine**, because CI only updates a function that already exists.

   ```bash
   infra/scripts/release.sh
   curl $(terraform -chdir=infra/app output -raw url)/health   # {"status":"ok"}
   ```

7. **Run the Deploy workflow once by hand** (Actions > Deploy > Run workflow, on `main`, `ref` empty) to check that CI can sign in.

If a role is refused a `lambda:` or `logs:` action, add it in `bootstrap/deploy-role.tf` (or `plan-role.tf`) and apply the bootstrap again: the permission lists haven't been run against a real account yet.

## Change the bootstrap

CI never applies the bootstrap, so you do, after any change to its `.tf` files. This includes the first deploy after moving from ECS and RDS: the CI roles' permissions changed from ECS and ECR to Lambda, and CI will be refused until you apply them.

```bash
terraform -chdir=infra/bootstrap plan
terraform -chdir=infra/bootstrap apply
```

The access keys and GitHub settings stay as they are.

## Deploy

**App changes:** merge to `main`. Once CI passes, the Deploy workflow ships it. Or from your machine: commit, then run `infra/scripts/release.sh`. It builds the zip with `infra/scripts/build-zip.sh` and applies `infra/app`.

**Infrastructure changes** (`bootstrap/` or `foundation/`): CI never applies these. Plan and apply them yourself, before merging anything that needs them:

```bash
terraform -chdir=infra/foundation plan
terraform -chdir=infra/foundation apply
```

## Rotate the CI access keys

Repeat step 4 (a user can hold two keys, so the old one works until you delete it), then delete the old key: `aws iam delete-access-key --user-name <user> --access-key-id <old key id>`, with the id from `aws iam list-access-keys --user-name <user>`.

## Rollback

A deploy switches all traffic to the new code at once. If the new code is broken, the Deploy run fails its `/health` check, but the broken code keeps running until you roll back. Either:

- **Revert the bad commit on `main`.** CI tests and deploys the revert like any other change.
- **Redeploy an earlier commit.** Run the Deploy workflow by hand and set `ref` to that commit. It must be on `main` and from after the move to Lambda; the workflow refuses commits from other branches.

A rollback changes the code, not the links in the table. So a change to how links are stored must still work with the previous code.

## Tear down

App first, then the foundation (the function uses the foundation's role):

```bash
terraform -chdir=infra/app destroy -var app_version=none -var package_hash=none
terraform -chdir=infra/foundation destroy
```

If the table has deletion protection on, set `table_deletion_protection = false` in `infra/foundation/terraform.tfvars` and apply first. Destroying the table deletes the links, and its point-in-time backups with them.

The bootstrap stays; it costs almost nothing. To remove it too, delete the two users' access keys (Terraform can't delete a user that has one), move its state back to your machine first (it can't be in the bucket it deletes): recreate `backend_override.tf` as in step 1, run `terraform -chdir=infra/bootstrap init -migrate-state`, empty the bucket (versions included), then run `terraform destroy` in `infra/bootstrap`.

Then check nothing is left; it should print nothing:

```bash
aws resourcegroupstaggingapi get-resources --region eu-north-1 --tag-filters Key=Project,Values=url-shortener --query 'ResourceTagMappingList[].ResourceARN' --output text
```

It lists the state bucket while the bootstrap exists, and can list deleted resources for a few hours; if `terraform state list` is empty in `app/` and `foundation/`, they're stale.

## Cost

On-demand `eu-north-1` (Stockholm) prices from the AWS Price List, November 2026.

- **Practice:** about $0. Lambda and DynamoDB charge per request and have no idle cost, and the function URL is free.
- **Full scale, without a CDN:** about $12,000/month, about twice the old ECS and RDS stack (about $6,200): Lambda requests ~$6,100 (about 30 billion a month), data transfer out ~$2,650, DynamoDB ~$2,300, Lambda run time ~$800.
- **Full scale, behind a CDN** that answers most redirects from its cache, the origin costs about $1.2k/month, about the same as ECS and RDS did. That is why the design assumes a CDN ([ADR 0006](../docs/decisions/0006-move-to-lambda-and-dynamodb.md)).

Set a budget alert in the AWS console.
