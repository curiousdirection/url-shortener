# 1. Run database migrations on every app task at startup

Date: 2026-11-12. Status: accepted.

## Context

The app runs as ECS Express Mode tasks on Fargate. The database is RDS Postgres in private subnets: it has no route to the internet, and its security group only accepts the app tasks. So migrations can't be run from a laptop or from CI outside the VPC. They have to run from inside it.

Tasks come and go (scale-out, releases, replacements), so no task is special.

## Decision

Each task runs `node dist/migrate.js` in the container's start command, before it starts the app. If the migration fails the container exits, so the task never becomes healthy and Express Mode rolls the release back.

## Why

- **Migrations must run inside the VPC.** The database is private, so a laptop or CI outside the VPC can't reach it without a tunnel or a public database. The tasks are already inside, with network access to the database and permission to read its password (from SSM Parameter Store).
- **At startup, a release stays one step.** A release is `release.sh` (which ends in `terraform apply`), with no separate migration step to remember. Running one migration with ECS Exec in a single task would also work with a private database, but it adds a step to every release.
- **Code and schema travel together.** Each task runs the migrations shipped in its own release.

## Consequences

- **Tasks that start together race.** `runMigrations()` in `src/migrator.ts` takes a Postgres advisory lock, so several tasks can run it at once. With one task starting at a time (the practice defaults) there is no race; the lock matters at larger sizes.
- **Old and new code overlap.** Old tasks keep serving while the first new task migrates, so every migration must work with both the old and the new code. This holds for any approach that migrates before a rollout, not just this one. Renames, drops and type changes take two releases: add first, remove in a later one.
- **A committed migration stays applied** even if the release is rolled back, so it must also work with the previous version. A migration that fails rolls back its own transaction.
- **The app's database user can change the schema**, because the same credentials run the migrations. A separate migration user would need a second secret.
- **Every start runs the migrator**, including scale-out. It finds nothing to apply and costs a few seconds and one database connection.

## Alternatives considered

- **One migration run before the rollout**, from a single task over ECS Exec (for example scripted from `release.sh`). This works with the private database and is the closest alternative. No lock is needed, but it adds a step to every release (or more script in `release.sh`), the first deploy still needs a task to run it from, and the old/new compatibility rule still applies.
- **A bastion host or SSM port forward** from a laptop or CI. This also works with a private database, but the migration runs outside the VPC, so the database password has to be handled outside AWS and there is more to set up than running it in a task.
- **A public database,** so that a laptop or CI could run migrations directly. Rejected: it exposes the database to the internet only to run migrations, and a private database is the point of the network layout.
- **A migration tool such as Flyway or node-pg-migrate** would replace the hand-written migrator, and possibly the lock. It would not change where the migrations run.

## Revisit when

There are many migrations or risky schema changes, several people write migrations, least-privilege database users become a requirement, or CI can run inside the VPC.
