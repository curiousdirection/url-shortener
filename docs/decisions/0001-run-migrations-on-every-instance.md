# 1. Run database migrations on every app instance at boot

Date: 2026-11-12. Status: accepted.

## Context

The app runs on EC2 servers in an auto scaling group. The database is RDS Postgres in private subnets: it has no route to the internet, and its security group only accepts the app servers. So migrations can't be run from a laptop or from CI outside the VPC. They have to run from inside it.

Servers come and go (scale-out, rolling releases, replacements), so no server is special.

## Decision

Each server runs `node dist/migrate.js` in its boot script, after it installs the release and before it starts the app. If the migration fails (after 5 tries) the boot fails, so the server never becomes healthy and the rolling release is rolled back.

## Why

- **Migrations must run inside the VPC.** The database is private, so a laptop or CI outside the VPC can't reach it without a tunnel or a public database. The servers are already inside, with network access to the database and permission to read its password (from SSM).
- **At boot, a release stays one step.** A release is `release.sh` followed by `terraform apply`, with no separate migration step to remember. Running one migration over SSM Session Manager from a single server would also work with a private database, but it adds a step to every release.
- **Code and schema travel together.** Each server runs the migrations shipped in its own release.

## Consequences

- **Servers that boot together race.** `runMigrations()` in `src/migrator.ts` takes a Postgres advisory lock, so several servers can run it at once. With one server booting at a time (the practice defaults) there is no race; the lock matters at larger sizes.
- **Old and new code overlap.** Old servers keep serving while the first new server migrates, so every migration must work with both the old and the new code. This holds for any approach that migrates before a rollout, not just this one. Renames, drops and type changes take two releases: add first, remove in a later one.
- **A committed migration stays applied** even if the release is rolled back, so it must also work with the previous version. A migration that fails rolls back its own transaction.
- **The app's database user can change the schema**, because the same credentials run the migrations. A separate migration user would need a second secret.
- **Every boot runs the migrator**, including scale-out. It finds nothing to apply and costs a few seconds and one database connection.

## Alternatives considered

- **One migration run before the rollout**, from a single server over SSM Session Manager (for example scripted from `release.sh`). This works with the private database and is the closest alternative. No lock is needed, but it adds a step to every release (or more script in `release.sh`), the first deploy still needs a server to run it from, and the old/new compatibility rule still applies.
- **A bastion host or SSM port forward** from a laptop or CI. This also works with a private database, but the migration runs outside the VPC, so the database password has to be handled outside AWS and there is more to set up than running it on a server.
- **A public database,** so that a laptop or CI could run migrations directly. Rejected: it exposes the database to the internet only to run migrations, and a private database is the point of the network layout.
- **A migration tool such as Flyway or node-pg-migrate** would replace the hand-written migrator, and possibly the lock. It would not change where the migrations run.

## Revisit when

There are many migrations or risky schema changes, several people write migrations, least-privilege database users become a requirement, or CI can run inside the VPC.
