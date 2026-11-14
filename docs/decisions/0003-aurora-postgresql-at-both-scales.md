# 3. Aurora PostgreSQL at both scales

Date: 2026-11-14. Status: accepted. Replaces RDS for PostgreSQL ([0002](0002-deploy-with-ecs-express-mode.md) built the first version on it).

## Context

The database was RDS for PostgreSQL: a `db.t4g.micro` for practice, a Multi-AZ `db.r7g.large` for full scale. Two things were awkward. The database is private, so looking at the data meant a CloudShell session inside the VPC and `psql`. And practice cost money while idle, so the stack was destroyed between sessions and its data lost.

## Decision

Use Aurora PostgreSQL 16 at both scales, from the same Terraform in `infra/database.tf`. Only variable values differ:

| | Practice (defaults) | Full scale (`full-scale.tfvars.example`) |
| --- | --- | --- |
| Instance class | `db.serverless` | `db.r7g.large` |
| Instances | 1 | 2 (writer and a reader for failover) |
| Capacity | 0 to 2 ACU, pauses after 5 idle minutes | fixed |

The cluster has the RDS Data API on. The database user and password live in one Secrets Manager secret that Terraform makes. ECS reads the password from it, and the Data API can use it too.

## Why

- **Look at the data from the console.** The Data API runs SQL over HTTPS, so the query editor in the RDS console works with no network path into the VPC ("Look at the data" in [infra/README.md](../../infra/README.md)).
- **Practice can sit idle.** With a minimum of 0 ACU the database pauses and costs only storage, and keeps its data.
- **Same Terraform at both scales.** Practice and full scale are still the same files with different values.

## Consequences

- **A cold start.** The first request after a pause waits about 15 seconds while the database resumes, and 30 seconds or more after a day paused. The app needs nothing for this: `pg` has no connect timeout by default, so it waits, and the pool closes idle connections after 10 seconds, so the database can pause. The load balancer's health check (`/health`) doesn't touch the database. A client left connected, such as a `psql` session, keeps the database awake.
- **I/O charges at full scale.** Aurora Standard bills each I/O. I/O-Optimized has none but costs more per hour. See "Cost" in [infra/README.md](../../infra/README.md).
- **Practice needs the Paid plan.** On the Free plan Aurora only works for clusters from the console's express configuration, which Terraform doesn't use.
- **Replacing a running stack deletes its data.** The database is replaced, not migrated. That is fine for practice test data; at full scale it would need a snapshot restore.
- **Failover needs a second instance.** Practice has one instance and no failover; full scale has two.

## Alternatives considered

- **Keep RDS for PostgreSQL.** Nothing needs to change, but there is no Data API, and practice either costs money while idle or is destroyed between sessions.

## Revisit when

The cold start bothers real users (set the minimum to 0.5 ACU so it never pauses), the I/O bill is a large part of the database's cost (switch to I/O-Optimized), or Aurora's pause rules change.
