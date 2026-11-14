# 3. Split the Terraform stacks, keep state in S3 and deploy from CI

Date: 2026-11-14. Status: accepted; amends [0002](0002-deploy-with-ecs-express-mode.md).

## Context

[0002](0002-deploy-with-ecs-express-mode.md) deployed the app with one Terraform stack and a script run from a laptop. The state was a local file, because it held the database password in plain text. Every release meant a person with admin credentials running `release.sh`.

We want a push to `main` to ship the app. CI can't use a local state file, and it shouldn't hold admin credentials. A release changes the image tag. The network, the database and the IAM roles change rarely, and a mistake there is expensive (a replaced database loses its data).

## Decision

- **Three stacks, each with its own state.** `infra/bootstrap` (the state bucket, GitHub's sign-in and two CI roles), `infra/foundation` (VPC, database, security groups, the two ECS roles, the password parameter) and `infra/app` (ECR, log group, the ECS Express service). `app` reads the foundation's outputs with `terraform_remote_state`.
- **State in S3** with versioning, encryption, public access blocked, HTTPS only, and locking with a lock file (`use_lockfile`, so no DynamoDB table). The bootstrap's own state stays local: it holds no secrets and can't live in a bucket that doesn't exist yet.
- **No password in state.** The password is an `ephemeral "random_password"`, passed to `aws_db_instance` as `password_wo` and to `aws_ssm_parameter` as `value_wo`. Both are write-only: sent to AWS, never written to the plan or the state. A `*_version` argument controls when they are sent again.
- **CI applies only the app stack.** `.github/workflows/deploy.yml` runs on a push to `main` that changes the app, tests, builds the image, plans, applies the saved plan and checks `/health`. You apply the foundation from your machine, after reading its plan on the pull request.
- **GitHub signs in with OIDC, with two roles.** `github-deploy-url-shortener` can be assumed only by the `production` environment on `main`. It can push images and update the one service, and pass the two ECS roles to ECS. `github-plan-url-shortener` can be assumed by any pull request of this repository and is read-only. Neither can change IAM or the bootstrap.
- **Every action is pinned to a commit SHA.**

## Why

- **A release can't break the foundation.** The deploy role has no permission on the network, the database or IAM, so a bad commit or a leaked token can at worst push an image and update one service.
- **The password never reaches S3 or the logs.** Locking down a bucket that holds secrets is a weaker answer than not putting them there, and the state also goes to CI and to its logs.
- **A person reads every infrastructure change.** The foundation plan appears on each pull request, and applying it is a deliberate step.
- **No stored keys.** OIDC gives each run credentials that expire in an hour.
- **Canary and rollback stay.** Express Mode's canary and automatic rollback are unchanged, and a rolled-back release fails the run.

## Consequences

- **The foundation is applied by hand.** If an app change needs a foundation change, the foundation must be applied before the merge. The pull request plan shows it.
- **The deploy role can't create the service.** CI only updates a service that exists. If the stack is torn down, a push ends green with a note ("the app is not deployed") and changes nothing. Bringing it back is `release.sh`, on purpose: a stray push shouldn't start a bill. A change that would replace the service also fails in CI, instead of taking the app down.
- **The plan role can read the database password.** Terraform refreshes the password parameter, and the default AWS-managed key lets any role with `ssm:GetParameter` decrypt it. So any pull request in this repository can read the password. The database is private and only the app tasks can reach it, so this is accepted for a one-person practice setup. A customer-managed key that the plan role can't use would close it, but then the foundation plan can't refresh the parameter.
- **A new password breaks running tasks** until they are replaced, because they read the password when they start. See "Rotate the database password" in [infra/README.md](../../infra/README.md).
- **If the database is replaced**, the parameter is replaced with it (`replace_triggered_by`), so the two keep the same password.
- **The first runs need care.** Repositories created or renamed after 15 July 2026 sign in with an ID-based `sub` claim, and the roles' permission lists were written from the docs and not run against AWS. Both are checked on the first run ([infra/README.md](../../infra/README.md)).
- **Pushes queue.** One deploy runs at a time, and GitHub keeps only the newest waiting run.
- **One AWS account holds everything**, so the roles' limits are the only wall between CI and the rest of the account.

## Alternatives considered

- **One stack, applied by CI.** The CI role would need to create networks, databases and IAM roles, and one bad commit could replace the database.
- **Keep the password in state and lock the bucket down.** It works, but AWS's Terraform guidance says not to, and the state is read by CI.
- **An RDS-managed password** (`manage_master_user_password`). RDS rotates it every 7 days and running tasks keep the old one, unless the app re-reads the secret on an authentication failure.
- **IAM database authentication for the app.** The strongest (no app password at all), but `src/db.ts` would have to create a token per connection. A good next step.
- **A workflow that applies the foundation**, behind a required reviewer. It would need a third role that can create IAM roles, capped with a permissions boundary. Not needed while the foundation changes rarely.
- **A permissions boundary on the CI roles.** Not needed: they can't create roles, and an explicit deny blocks every IAM write.
- **Access keys in GitHub secrets.** Long-lived, and they leak.
- **Ask for a manual approval on each deploy.** The canary already rolls back bad releases. A required reviewer on `production` can be added later in GitHub, with no code change.

## Revisit when

The project goes beyond practice (use a separate AWS account for CI, and image scanning in ECR), the foundation changes often enough that applying it by hand is a chore, or drift between the state and AWS needs checking on a schedule.
