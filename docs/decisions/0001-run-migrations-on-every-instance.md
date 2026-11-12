# 1. Run database migrations on every app instance at boot

Date: 2026-11-12. Status: accepted.

## Context

The app runs on EC2 servers in an auto scaling group. The database is RDS Postgres in private subnets: it has no route to the internet, and its security group only accepts the app servers. So migrations can't be run from a laptop or from CI outside the VPC. They have to run from inside it.

Servers come and go (scale-out, rolling releases, replacements), so no server is special.

## Decision

Each server runs `node dist/migrate.js` in its boot script, after it installs the release and before it starts the app. If the migration fails (after 5 tries) the boot fails, so the server never becomes healthy and the rolling release is rolled back.

## Why

- **The database is private.** The servers are the only things that already have network access to it and permission to read its password (from SSM). Nothing extra has to be built or run.
- **One step per release.** A release is `release.sh` followed by `terraform apply`. There is no separate migration step, bastion host or tunnel to remember.
- **Code and schema travel together.** Each server runs the migrations shipped in its own release.

## Consequences

- **Servers that boot together race.** `runMigrations()` in `src/migrator.ts` takes a Postgres advisory lock, so several servers can run it at once. With one server booting at a time (the practice defaults) there is no race; the lock matters at larger sizes.
- **Old and new code overlap.** Old servers keep serving while the first new server migrates, so every migration must work with both the old and the new code. This holds for any approach that migrates before a rollout, not just this one. Renames, drops and type changes take two releases: add first, remove in a later one.
- **A committed migration stays applied** even if the release is rolled back, so it must also work with the previous version. A migration that fails rolls back its own transaction.
- **The app's database user can change the schema**, because the same credentials run the migrations. A separate migration user would need a second secret.
- **Every boot runs the migrator**, including scale-out. It finds nothing to apply and costs a few seconds and one database connection.

## Alternatives considered

- **One migration run before the rollout**, for example on an existing server through SSM Session Manager. No lock is needed, but it adds a step to every release, the first deploy still needs a server to run it from, and the old/new compatibility rule still applies.
- **A bastion host or SSM port forward** from a laptop or CI. This needs a way into the VPC and handles the database password outside AWS.
- **A public database.** Rejected: a private database is the point of the network layout.
- **A migration tool such as Flyway or node-pg-migrate** would replace the hand-written migrator, and possibly the lock. It would not change where the migrations run.

## Revisit when

There are many migrations or risky schema changes, several people write migrations, least-privilege database users become a requirement, or CI can run inside the VPC.
