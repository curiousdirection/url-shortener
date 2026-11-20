# Deploying to AWS

Runs the app and its web page. The app is one [AWS Lambda](https://docs.aws.amazon.com/lambda/latest/dg/welcome.html) function with a function URL, behind an [Amazon CloudFront](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/Introduction.html) distribution, and keeps the links in a DynamoDB table. The page is files in an S3 bucket behind the same distribution. Why: [ADR 0006](../docs/decisions/0006-move-to-lambda-and-dynamodb.md), [ADR 0007](../docs/decisions/0007-cdn-cloudfront.md) and [ADR 0009](../docs/decisions/0009-frontend-on-s3.md). Practice uses the defaults in the `variables.tf` files; the `full-scale.tfvars.example` files show full-scale settings (reference only).

```
Internet -> CloudFront (*.cloudfront.net; AWS WAF rate limits at full scale) -> function URL (signed) -> Lambda function -> DynamoDB table
                                                    \-> S3 bucket (signed): the web page
```

CloudFront is the only way in: the function URL and the bucket refuse unsigned calls.

A push to `main` that changes the app is deployed by GitHub Actions, on a runner that CodeBuild hosts in this account, so CI holds no AWS keys. Why it is built this way: [ADR 0003](../docs/decisions/0003-split-stacks-remote-state-and-ci-deploys.md) and [ADR 0011](../docs/decisions/0011-deploy-on-a-codebuild-runner.md).

## The three stacks

| Folder | What is in it | Who applies it |
| --- | --- | --- |
| `bootstrap/` | The S3 state bucket, the CodeBuild runner that the deploy job runs on, the deploy role it signs in as, and the connection to GitHub | You, once (and again when its permissions change) |
| `foundation/` | The DynamoDB table and the function's IAM role | You, from your machine |
| `app/` | The Lambda function, its function URL, its log group, the web page's S3 bucket, the CloudFront distribution, its access logs (not at full scale) and (at full scale) the AWS WAF web ACL | GitHub Actions on push to `main`, or you with `scripts/release.sh` |

All three states are in the S3 bucket.

## Prerequisites

- Terraform via [tfenv](https://github.com/tfutils/tfenv): run `tfenv install` in the repo (1.11 or newer).
- Node.js at the version in `.node-version` (the zip is built on your machine for `release.sh`), `zip` and `openssl`.
- An AWS CLI profile that can create the resources (admin is simplest), and git.
- Your account's region (AWS Settings > Project). The default is `eu-north-1`; to change it, put `region = "..."` in a `terraform.tfvars` in each stack folder.
- Everything used is allowed on the AWS Free plan ([list](https://docs.aws.amazon.com/accounts/latest/reference/supported-services-sign-up-new.html)).

## Set up and first run

Do these once, in order, on a commit that is on `main`.

1. **Apply the bootstrap.** Its state bucket doesn't exist yet, so this first apply keeps the state locally, through a gitignored override file. Create the GitHub connection first and approve it, because the runner's webhook can't be made through a pending connection.

   ```bash
   printf 'terraform {\n  backend "local" {}\n}\n' > infra/bootstrap/backend_override.tf
   terraform -chdir=infra/bootstrap init
   terraform -chdir=infra/bootstrap apply -target=aws_codeconnections_connection.github
   ```

   Then approve the connection: in the console, open Developer Tools > Settings > Connections (in the stack's region), choose the pending `url-shortener-github` and "Update pending connection". This installs the AWS Connector for GitHub app; give it access to this repository. Then apply the rest:

   ```bash
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

3. **Set up GitHub.** Under Settings > Actions > General, set "Fork pull request workflows from outside collaborators" to "Require approval for all external contributors" (the default only asks first-time contributors). Under Settings > Environments, create `production` and limit its deployment branches to `main`. Then add these variables (none are secret) under Settings > Secrets and variables > Actions:

```bash
gh variable set AWS_REGION --body eu-north-1
gh variable set TF_STATE_BUCKET --body "$(terraform -chdir=infra/bootstrap output -raw state_bucket)"
```

4. **Apply the foundation.** Read the plan first. It takes a few seconds.

   ```bash
   terraform -chdir=infra/foundation apply
   ```

5. **Create the function, the bucket and the CDN from your machine**, because CI only updates what already exists. CloudFront takes about 5 to 15 minutes to deploy, and Terraform waits for it, so the apply seems stuck on the distribution; that is normal. The same wait applies to any later change to the distribution.

   ```bash
   infra/scripts/release.sh # yes
   curl $(terraform -chdir=infra/app output -raw url)/health   # {"status":"ok"}
   curl -i $(terraform -chdir=infra/app output -raw url)/      # text/html, with <meta name="release">
   ```

   `release.sh` also uploads the web page.

6. **Run CI once by hand** (Actions > CI > Run workflow, on `main`, `ref` empty). It runs the checks and then deploys, so it shows that the runner starts and can sign in. A deploy that a merge to `main` starts is a different event, so check the first one of those too: see [If the deploy job never starts](#if-the-deploy-job-never-starts).

If the role is refused a `lambda:`, `logs:` or `s3:` action, add it in `infra/bootstrap/deploy-role.tf` and apply the bootstrap again: the permission list hasn't been run against a real account yet.

## Change the bootstrap

CI never applies the bootstrap, so you do, after any change to its `.tf` files. 

```bash
terraform -chdir=infra/bootstrap plan
terraform -chdir=infra/bootstrap apply
```

The GitHub settings stay as they are.

## Deploy

**App changes:** merge to `main`. Once its checks pass, CI ships it: a `build` job on GitHub's runners makes the zip and the page, then a `deploy` job on the CodeBuild runner applies and uploads them. Its logs are also in the `/aws/codebuild/url-shortener-deploy` log group. If the `deploy` job never starts, see [If the deploy job never starts](#if-the-deploy-job-never-starts). Or from your machine: commit, then run `infra/scripts/release.sh`. It builds the zip with `infra/scripts/build-zip.sh` and applies `infra/app`.

**Web page changes** (`web/`): merge to `main`. After the app deploy, CI uploads the page it built with `infra/scripts/release-web.sh`, clears CloudFront's copy of `index.html` and checks that `/` serves the new release. It skips when nothing in `web/` (or its build) changed. From your machine, `release.sh` does the same after its apply. The caching is in [ADR 0009](../docs/decisions/0009-frontend-on-s3.md).

A change to CloudFront takes a few minutes to reach every location; CI's `/health` check runs after that.

### If the deploy job never starts

It waits for a CodeBuild runner, and the `watchdog` job cancels the run after 15 minutes (cancel one by hand with `gh run cancel <run id>`). A runner starts only for a workflow named `CI`. Check the runner project's webhook in the CodeBuild console and that the connection is still approved.

**Rate limits** are off for practice. To try them, set `rate_limiting = true` in `infra/app/terraform.tfvars`, run `release.sh`, then set it back. The limits are variables in `infra/app/variables.tf`.

**Access logs** (`cdn_access_logs`) are on for practice and off at full scale. Turning them on or off creates or deletes resources, which CI can't do: change the setting in `infra/app/terraform.tfvars` and run `release.sh`. A change can take up to 12 hours to reach CloudFront, so the first lines may be slow to appear.

To read them, use the AWS CLI: the Free plan's console doesn't show us-east-1, but the API works there. For example, the API requests of the last hour (method, path, status, `time-taken`, `origin-fbl`):

```bash
aws logs tail url-shortener-cdn-access --region us-east-1 --since 1h --format short | cut -d' ' -f2- | jq -r 'select(."cs-uri-stem" | startswith("/api/")) | [."cs-method", ."cs-uri-stem", ."sc-status", ."time-taken", ."origin-fbl"] | @tsv'
```

Without the `cut` and `jq`, it prints every line with all its fields; add `--follow` to keep watching.

`time-taken` is the whole request as CloudFront saw it; `origin-fbl` is the part spent waiting for the function URL. To find one request, match `x-edge-request-id` to the `x-amz-cf-id` header of its response.

**Take down a link:** delete it from the table, then clear CloudFront's copy:

```bash
aws cloudfront create-invalidation --distribution-id "$(terraform -chdir=infra/app output -raw distribution_id)" --paths "/<code>"
```

**Infrastructure changes** (`bootstrap/` or `foundation/`): CI never applies these. Plan and apply them yourself, before merging anything that needs them:

```bash
terraform -chdir=infra/foundation plan
terraform -chdir=infra/foundation apply
```

## Move an existing setup off access keys

For a setup made before [ADR 0011](../docs/decisions/0011-deploy-on-a-codebuild-runner.md), which has the two IAM users and their keys. In this order, with admin credentials and this change checked out. From step 2 until the merge, deploys can't sign in, so go straight through.

1. **Create the connection**, as in step 1 of "Set up and first run": run `terraform -chdir=infra/bootstrap apply -target=aws_codeconnections_connection.github`, then approve it in the console. Also set "Require approval for all external contributors" (step 3 there).
2. **Delete the two users' access keys.** Terraform can't delete a user that has one, so this must come before the apply that removes the users (names are for the default `name`).

   ```bash
   for user in github-deploy-url-shortener github-plan-url-shortener; do
     for key in $(aws iam list-access-keys --user-name "$user" --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
       aws iam delete-access-key --user-name "$user" --access-key-id "$key"
     done
   done
   ```

3. **Apply the bootstrap.** It makes the runner, changes the deploy role's trust to it, and removes the plan role and both users.

   ```bash
   terraform -chdir=infra/bootstrap apply
   ```

4. **Merge** the change to `main`. The old Deploy workflow can't sign in any more, so the merge is what brings deploys back.
5. **Run CI once by hand** (Actions > CI > Run workflow, on `main`, `ref` empty) and check that a runner starts. Then check the deploy after the next merge to `main` does too. If one doesn't, see [If the deploy job never starts](#if-the-deploy-job-never-starts).
6. **Delete the old GitHub settings.**

   ```bash
   gh secret delete AWS_DEPLOY_ACCESS_KEY_ID --env production
   gh secret delete AWS_DEPLOY_SECRET_ACCESS_KEY --env production
   gh secret delete AWS_PLAN_ACCESS_KEY_ID
   gh secret delete AWS_PLAN_SECRET_ACCESS_KEY
   gh variable delete AWS_DEPLOY_ROLE_ARN --env production
   gh variable delete AWS_PLAN_ROLE_ARN
   ```

## Rollback

A deploy switches all traffic to the new code at once. If the new code is broken, the CI run fails its `/health` check, but the broken code keeps running until you roll back. Either:

- **Revert the bad commit on `main`.** CI tests and deploys the revert like any other change.
- **Redeploy an earlier commit.** Run CI by hand (Actions > CI > Run workflow, on `main`) and set `ref` to that commit. It must be on `main` and from after the move to Lambda; the workflow refuses commits from other branches. A rollback skips the tests, so a broken `main` can't block it.

A rollback changes the code, not the links in the table. So a change to how links are stored must still work with the previous code.

## Tear down

App first, then the foundation (the function uses the foundation's role):

```bash
terraform -chdir=infra/app destroy -var app_version=none -var package_hash=none
terraform -chdir=infra/foundation destroy
```

Destroying the app takes several minutes, because CloudFront disables and then deletes the distribution. It also empties and deletes the web bucket, which `force_destroy` allows because the page can be rebuilt.

If the table has deletion protection on, set `table_deletion_protection = false` in `infra/foundation/terraform.tfvars` and apply first. Destroying the table deletes the links, and its point-in-time backups with them.

The bootstrap stays; it costs almost nothing. To remove it too, move its state back to your machine first (it can't be in the bucket it deletes): recreate `backend_override.tf` as in step 1, run `terraform -chdir=infra/bootstrap init -migrate-state`, empty the bucket (versions included), then run `terraform destroy` in `infra/bootstrap`.

Then check nothing is left; it should print nothing:

```bash
aws resourcegroupstaggingapi get-resources --region eu-north-1 --tag-filters Key=Project,Values=url-shortener --query 'ResourceTagMappingList[].ResourceARN' --output text
```

It lists the state bucket while the bootstrap exists, and can list deleted resources for a few hours; if `terraform state list` is empty in `app/` and `foundation/`, they're stale.

## Cost

On-demand `eu-north-1` (Stockholm) prices from the AWS Price List, November 2026.

- **Practice:** about $0. Lambda and DynamoDB charge per request and have no idle cost, the function URL is free, and CloudFront's free tier covers 10 million requests and 1 TB a month. The web bucket and the invalidations on each release (the first 1,000 paths a month are free) cost about $0. Access logs cost well under a cent a month at this traffic. AWS WAF is off; turned on (`rate_limiting = true`), it costs about $7 a month ($5 for the web ACL, $1 for each of its 2 rules, plus $0.60 per million requests).
- **Full scale, behind CloudFront** (pay-as-you-go, `full-scale.tfvars.example`), using the prices of [CloudFront](https://aws.amazon.com/cloudfront/pricing/pay-as-you-go/) and [AWS WAF](https://aws.amazon.com/waf/pricing/) (November 2026).
  - **CloudFront requests:** about $36,500/month for about 30 billion HTTPS requests in Europe ($0.012 per 10,000), plus about $2,500 of data transfer.
  - **AWS WAF:** about $18,000/month: $5 for the web ACL, $1 for each of 2 rules, and $0.60 per million requests inspected. Every request counts, cached or not.
  - **Origin Shield:** $0.009 per 10,000 requests in Europe, about $2,700/month if 10% of requests reach it.
  - **Access logs** are off. On, they would cost about $5,000/month: about 10 TB of log lines (a guess of 330 bytes each) at $0.50 per GB, the first tier of [CloudWatch's vended logs](https://aws.amazon.com/cloudwatch/pricing/).
  - **Origin (Lambda, DynamoDB):** about $1.2k/month, assuming 90% of redirects come from the cache (a guess; [ADR 0007](../docs/decisions/0007-cdn-cloudfront.md)).
- **Full scale, without a CDN**, for comparison: about $12,000/month, about twice the old ECS and RDS stack (about $6,200): Lambda requests ~$6,100 (about 30 billion a month), data transfer out ~$2,650, DynamoDB ~$2,300, Lambda run time ~$800.