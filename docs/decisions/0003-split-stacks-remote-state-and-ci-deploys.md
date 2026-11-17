# 3. Split the Terraform stacks, keep state in S3 and deploy from CI

Date: 2026-11-14. Status: accepted; amends [0002](0002-deploy-with-ecs-express-mode.md).

## Context

[0002](0002-deploy-with-ecs-express-mode.md) deployed the app with one Terraform stack and a script run from a laptop. The state was a local file, because it held the database password in plain text, and every release needed a person with admin credentials.

We want a push to `main` to ship the app. CI can't use a local state file and shouldn't hold admin credentials. A release only changes the image; the network, the database and the IAM roles change rarely, and a mistake there is expensive.

## Decision

- **Three stacks, each with its own state.** `infra/bootstrap` (state bucket, GitHub sign-in, CI roles), `infra/foundation` (network, database, ECS roles, password parameter) and `infra/app` (ECR, logs, the ECS Express service).
- **State in S3**, encrypted, versioned, private, with S3 native locking. The bootstrap's own state starts local, because the bucket doesn't exist yet, and moves into the bucket after the first apply.
- **No password in state.** It is generated as an ephemeral value and sent with write-only arguments, so it never reaches the plan, the state or the logs.
- **CI applies only the app stack**, on a push to `main` that changes the app. You plan and apply the foundation from your machine.
- **GitHub signs in with OIDC, with two roles.** The deploy role is limited to the `production` environment on `main` and can only push images and update the one service. The plan role is for CI on any branch, is read-only, plans only the app stack and is denied every secret.

How each part works is in the code comments and [infra/README.md](../../infra/README.md).

## Why

- **A release can't break the foundation.** A bad commit or a leaked token can at worst push an image and update one service.
- **No secrets in state.** Not storing the password is a stronger answer than locking down the bucket that holds it.
- **No stored keys.** Each run gets credentials that expire within an hour.
- **A person applies every infrastructure change**, after reading its plan.

## Consequences

- **The foundation is applied by hand.** If an app change needs a foundation change, apply the foundation before merging.
- **CI won't recreate a torn-down stack.** A push then ends green with a note; bringing the stack back is `release.sh`, so a stray push can't start a bill.
- **No foundation plan in CI.** Refreshing it would decrypt the password, and any branch can use the plan role.
- **Rotating the password causes a short outage**, because running tasks read it once at start. See "Rotate the database password" in [infra/README.md](../../infra/README.md).
- **One AWS account holds everything**, so the roles' limits are the only wall between CI and the rest of the account.

## Alternatives considered

- **One stack, applied by CI.** The CI role would need to create networks, databases and IAM roles, and one bad commit could replace the database.
- **Keep the password in state and lock the bucket down.** AWS's Terraform guidance says not to, and CI reads the state.
- **An RDS-managed password.** RDS rotates it every 7 days, and running tasks keep the old one.
- **IAM database authentication for the app.** The app would have no password at all. A good next step, but it needs a dedicated database user and changes to `src/db.ts`.

## Revisit when

The project goes beyond practice (a separate AWS account, image scanning), or the foundation changes often enough that applying it by hand is a chore.
