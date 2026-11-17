# 5. Log in to the database with IAM tokens, as a dedicated user

Date: 2026-11-17. Status: accepted; amends [0003](0003-split-stacks-remote-state-and-ci-deploys.md).

## Context

App tasks logged in as the RDS master user, with the password passed in as `PGPASSWORD` when the task started. That had two problems. Rotating the password broke every new connection until the tasks were replaced ([0003](0003-split-stacks-remote-state-and-ci-deploys.md)). And the app ran with the master user's rights over the whole database.

## Decision

- **The app logs in as its own database user, `app`, with an IAM token.** `src/db.ts` makes a token (valid 15 minutes) for each new connection, signed by the task's IAM role, which may connect as `app` to this one database and do nothing else. There is no password in the task.
- **A one-off ECS task creates `app`.** It runs `node dist/setupDb.js` from the same image, as the master user, and gives `app` the schema and the tables that already exist (`src/appRole.ts`). `infra/scripts/release.sh` runs it before every apply, so it also sets up a new database. It is the only reader of the password parameter, through its own execution role.
- **Migrations still run when each task starts** ([0001](0001-run-migrations-on-every-instance.md)), now as `app`.
- **Keep `db.t4g.micro` for practice.** See the first consequence.

## Why

- **Rotation stops mattering to running tasks.** Only the setup task uses the password, and it reads it fresh each run.
- **Someone has to create `app`, and only the master user can.** Terraform runs outside the VPC and the database is private. Creating it from the app tasks would leave the master password in them.
- **A task run from `release.sh`, not CI.** CI's deploy role can neither pass the setup task's execution role nor run tasks, so it still can't read the password.

## Consequences

- **The database needs more memory.** AWS says IAM authentication takes 300-1000 MiB of extra memory for reliable connections, and `db.t4g.micro` has 1 GiB in total ([source](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.html)). Watch `FreeableMemory` after the first release. If it runs low or logins fail now and then, move practice to `db.t4g.small`, which costs more and may leave the free plan. Full scale is not affected.
- **No rollback past this release.** Older images expect `PGPASSWORD`, which the service no longer provides, so `app_version` can't go back across it. To go back, revert the PR and release.
- **A release also runs a task**, which adds about a minute, and the person running `release.sh` needs permission to run ECS tasks.
- **New connections are rate-limited by RDS** when they use IAM. The pool reuses connections, so new ones are rare; revisit at full scale.

## Alternatives considered

- **Keep `PGPASSWORD` for one release as a bridge.** Rollback would work, but the password would stay in the tasks, which is what this removes.
- **Create `app` when the app starts.** The tasks would need the master password.
- **Run the setup from CI.** CI would need the password and permission to run tasks.
- **An RDS-managed master password.** It rotates every 7 days and running tasks keep the old one; it does not give the app its own user.

## Revisit when

`FreeableMemory` is a problem, new connection rates get near RDS's limit at full scale, or the app needs a second database user (for example read-only).
