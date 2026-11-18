# Deploying to AWS

Runs the app as one [AWS Lambda](https://docs.aws.amazon.com/lambda/latest/dg/welcome.html) function with a function URL, behind an [Amazon CloudFront](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/Introduction.html) distribution, and keeps the links in a DynamoDB table. Why: [ADR 0006](../docs/decisions/0006-move-to-lambda-and-dynamodb.md) and [ADR 0007](../docs/decisions/0007-cdn-cloudfront.md). Practice uses the defaults in the `variables.tf` files; the `full-scale.tfvars.example` files show full-scale settings (reference only).

```
Internet -> CloudFront (*.cloudfront.net; AWS WAF rate limits at full scale) -> function URL (signed) -> Lambda function -> DynamoDB table
```

CloudFront is the only way in: the function URL refuses unsigned calls.

A push to `main` that changes the app is deployed by GitHub Actions. Why it is built this way: [ADR 0003](../docs/decisions/0003-split-stacks-remote-state-and-ci-deploys.md).

## The three stacks

| Folder | What is in it | Who applies it |
| --- | --- | --- |
| `bootstrap/` | The S3 state bucket, the two CI roles and the IAM user that signs in as each | You, once (and again when its permissions change) |
| `foundation/` | The DynamoDB table and the function's IAM role | You, from your machine |
| `app/` | The Lambda function, its function URL, its log group, the CloudFront distribution and (at full scale) the AWS WAF web ACL | GitHub Actions on push to `main`, or you with `scripts/release.sh` |

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

2. **Move the state into the bucket.** Put the `state_bucket` output in `infra/backend.hcl` (`cp infra/backend.hcl.example infra/backend.hcl`) and in `infra/app/terraform.tfvars` (`touch infra/app/terraform.tfvars`) as `state_bucket = "..."`. Both files are gitignored.

   ```bash
   rm infra/bootstrap/backend_override.tf
   terraform -chdir=infra/bootstrap init -migrate-state -backend-config=../backend.hcl # yes
   rm -f infra/bootstrap/terraform.tfstate infra/bootstrap/terraform.tfstate.backup
   terraform -chdir=infra/foundation init -backend-config=../backend.hcl
   terraform -chdir=infra/app init -backend-config=../backend.hcl
   ```

3. **Set up GitHub.** Under Settings > Environments, create `production` and limit its deployment branches to `main`. Then add these variables (none are secret) under Settings > Secrets and variables > Actions:

```bash
gh variable set AWS_REGION --body eu-north-1
gh variable set TF_STATE_BUCKET --body "$(terraform -chdir=infra/bootstrap output -raw state_bucket)"
gh variable set AWS_PLAN_ROLE_ARN --body "$(terraform -chdir=infra/bootstrap output -raw plan_role_arn)"
gh variable set AWS_DEPLOY_ROLE_ARN --env production --body "$(terraform -chdir=infra/bootstrap output -raw deploy_role_arn)"
```

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

6. **Create the function and the CDN from your machine**, because CI only updates what already exists. CloudFront takes about 5 to 15 minutes to deploy, and Terraform waits for it, so the apply seems stuck on the distribution; that is normal. The same wait applies to any later change to the distribution.

   ```bash
   infra/scripts/release.sh # yes
   curl $(terraform -chdir=infra/app output -raw url)/health   # {"status":"ok"}
   ```

7. **Run the Deploy workflow once by hand** (Actions > Deploy > Run workflow, on `main`, `ref` empty) to check that CI can sign in.

If a role is refused a `lambda:` or `logs:` action, add it in `bootstrap/deploy-role.tf` (or `plan-role.tf`) and apply the bootstrap again: the permission lists haven't been run against a real account yet.

## Change the bootstrap

CI never applies the bootstrap, so you do, after any change to its `.tf` files. 

```bash
terraform -chdir=infra/bootstrap plan
terraform -chdir=infra/bootstrap apply
```

The access keys and GitHub settings stay as they are.

## Deploy

**App changes:** merge to `main`. Once CI passes, the Deploy workflow ships it. Or from your machine: commit, then run `infra/scripts/release.sh`. It builds the zip with `infra/scripts/build-zip.sh` and applies `infra/app`.

A change to CloudFront takes a few minutes to reach every location; the Deploy workflow's `/health` check runs after that.

**Rate limits** are off for practice. To try them, set `rate_limiting = true` in `infra/app/terraform.tfvars`, run `release.sh`, then set it back. The limits are variables in `infra/app/variables.tf`.

**Take down a link:** delete it from the table, then clear CloudFront's copy:

```bash
aws cloudfront create-invalidation --distribution-id "$(terraform -chdir=infra/app output -raw distribution_id)" --paths "/<code>"
```

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

Destroying the app takes several minutes, because CloudFront disables and then deletes the distribution.

If the table has deletion protection on, set `table_deletion_protection = false` in `infra/foundation/terraform.tfvars` and apply first. Destroying the table deletes the links, and its point-in-time backups with them.

The bootstrap stays; it costs almost nothing. To remove it too, delete the two users' access keys (Terraform can't delete a user that has one), move its state back to your machine first (it can't be in the bucket it deletes): recreate `backend_override.tf` as in step 1, run `terraform -chdir=infra/bootstrap init -migrate-state`, empty the bucket (versions included), then run `terraform destroy` in `infra/bootstrap`.

Then check nothing is left; it should print nothing:

```bash
aws resourcegroupstaggingapi get-resources --region eu-north-1 --tag-filters Key=Project,Values=url-shortener --query 'ResourceTagMappingList[].ResourceARN' --output text
```

It lists the state bucket while the bootstrap exists, and can list deleted resources for a few hours; if `terraform state list` is empty in `app/` and `foundation/`, they're stale.

## Cost

On-demand `eu-north-1` (Stockholm) prices from the AWS Price List, November 2026.

- **Practice:** about $0. Lambda and DynamoDB charge per request and have no idle cost, the function URL is free, and CloudFront's free tier covers 10 million requests and 1 TB a month. AWS WAF is off; turned on (`rate_limiting = true`), it costs about $7 a month ($5 for the web ACL, $1 for each of its 2 rules, plus $0.60 per million requests).
- **Full scale, behind CloudFront** (pay-as-you-go, `full-scale.tfvars.example`), using the prices of [CloudFront](https://aws.amazon.com/cloudfront/pricing/pay-as-you-go/) and [AWS WAF](https://aws.amazon.com/waf/pricing/) (November 2026).
  - **CloudFront requests:** about $36,500/month for about 30 billion HTTPS requests in Europe ($0.012 per 10,000), plus about $2,500 of data transfer.
  - **AWS WAF:** about $18,000/month: $5 for the web ACL, $1 for each of 2 rules, and $0.60 per million requests inspected. Every request counts, cached or not.
  - **Origin Shield:** $0.009 per 10,000 requests in Europe, about $2,700/month if 10% of requests reach it.
  - **Origin (Lambda, DynamoDB):** about $1.2k/month, assuming 90% of redirects come from the cache (a guess; [ADR 0007](../docs/decisions/0007-cdn-cloudfront.md)).
- **Full scale, without a CDN**, for comparison: about $12,000/month, about twice the old ECS and RDS stack (about $6,200): Lambda requests ~$6,100 (about 30 billion a month), data transfer out ~$2,650, DynamoDB ~$2,300, Lambda run time ~$800.