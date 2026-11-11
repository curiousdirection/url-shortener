# Plan: deploy to AWS with Terraform

## Context

This is a design exercise (see Assumptions in README.md). The goal is to practice running the app on AWS infrastructure we manage ourselves: servers, auto scaling, a load balancer and a database. It should be cheap enough to run on the AWS free plan credits ($100–200 over 6 months) and easy to tear down between practice sessions.

The same Terraform should describe the full-scale design. Practice and full scale differ only in variable values (instance sizes and counts), not in structure.

**Prerequisite:** the change that replaces the Redis counter with a Postgres sequence has been merged (no `src/redis.ts`, no `ioredis`). If Redis is still in the code, stop and ask before adding ElastiCache.

## Architecture

```
Internet ─► NLB (2 public subnets, 2 AZs)
              │ TCP :80 (and TLS :443 if a domain is set)
              ▼
            Auto Scaling group of EC2 (public subnets, SG: only from NLB)
              │ :5432
              ▼
            RDS Postgres 16 (private subnets, SG: only from app SG)
```

Choices and why:

- **NLB, not ALB.** At full scale most clicks are new connections. ALB allows 25 new connections/s per capacity unit: 11,600/s ÷ 25 ≈ 463 units × $0.008 × 730 h ≈ $2,700/month. NLB allows 800/s per unit, so its cost is driven by data processed instead: ~62 GB/h ≈ 62 units × $0.006 × 730 h ≈ $290/month. The app needs no HTTP routing, so ALB features aren't missed. HTTP health checks on `/health` work on NLB.
- **No NAT gateway** (~$0.045/h ≈ $33/month). App instances sit in public subnets with a public IP for outbound access (S3, SSM, nodejs.org). Their security group only accepts port 3000 from the NLB's security group.
- **No API Gateway, no Lambda.** The NLB covers routing, health checks and TLS. Per-request pricing at 1B requests/day costs ~$1,000/day for API Gateway HTTP APIs.
- **No SSH.** Use SSM Session Manager: an instance profile with `AmazonSSMManagedInstanceCore`, and no port 22 open.
- **DB password:** a `random_password` stored as an SSM Parameter Store SecureString (standard tier is free). Don't use RDS-managed Secrets Manager passwords: they rotate every 7 days by default, which breaks the connection string the app reads at boot. The password ends up in Terraform state, so state stays local and gitignored for now.

## Files

All under `infra/` unless noted.

| File | Contents |
|---|---|
| `versions.tf` | Terraform `>= 1.9`, AWS provider pinned to the current major (check the registry), `random` provider. Local state. |
| `variables.tf` | Every size/count below as a variable with practice defaults; `region` (default `us-east-1`); `app_version` (release id); optional `domain_name`; `budget_alert_email` (required, no default; never commit a real address). |
| `network.tf` | VPC `10.0.0.0/16`; 2 public + 2 private subnets across 2 AZs; internet gateway; public route table. No NAT. |
| `database.tf` | DB subnet group (private subnets); SG allowing 5432 only from the app SG; `aws_db_instance` (Postgres 16, `publicly_accessible = false`, gp3, `skip_final_snapshot`/`deletion_protection` from variables); `random_password` + `aws_ssm_parameter` (SecureString). |
| `app.tf` | S3 bucket for releases (`force_destroy = true`); IAM role + instance profile (SSM core, `s3:GetObject` on `releases/*`, `ssm:GetParameter` + `kms:Decrypt` on the DB password parameter); launch template (AL2023 arm64 AMI from SSM parameter `/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64`, IMDSv2 required, user data from template); ASG (`health_check_type = "ELB"`, grace 120 s, target-tracking on average CPU 60%, `instance_refresh` rolling with `min_healthy_percentage = 100`, `max_healthy_percentage = 200`, triggered by launch template changes). |
| `lb.tf` | NLB with security group, cross-zone on; target group TCP :3000 with HTTP health check `/health`, `deregistration_delay = 30`; listener :80. If `domain_name` is set: ACM certificate (DNS validation) and TLS listener :443. |
| `budget.tf` | `aws_budgets_budget`, monthly cost limit (default $10), email alerts at 80% actual and 100% forecast. |
| `outputs.tf` | NLB DNS name, `base_url`, RDS endpoint, release bucket name. |
| `user_data.sh.tftpl` | See "Boot sequence". |
| `terraform.tfvars.example` | Practice values. |
| `full-scale.tfvars.example` | Full-scale values (reference only, not meant to be applied). |
| `scripts/release.sh` | See "Releasing". |
| `README.md` | Prerequisites (AWS CLI profile, Terraform), first deploy, release, teardown, costs. |
| repo `.gitignore` | Add `infra/.terraform/`, `*.tfstate*`, `*.tfvars` (keep the `*.example` files). Commit `.terraform.lock.hcl`. |

### Variables: practice vs full scale

| Variable | Practice | Full scale | Why |
|---|---|---|---|
| `instance_type` | `t4g.micro` | `c7g.large` | Graviton, arm64 |
| `asg_min` / `asg_max` / `asg_desired` | 1 / 2 / 1 | 2 / 12 / 4 | Peak ~35k req/s ÷ ~2,000 req/s per vCPU ≈ 18 vCPU ≈ 9–10 × c7g.large, plus headroom. The per-vCPU figure is a guess until load-tested. |
| `db_instance_class` | `db.t4g.micro` | `db.r7g.large` | Free plan covers db.t4g.micro |
| `db_allocated_storage` | 20 | 300 | 1B rows × ~200 B (row + index) ≈ 200 GB, plus headroom |
| `db_multi_az` | false | true | |
| `db_backup_retention_days` | 1 | 7 | |
| `db_deletion_protection` / `db_skip_final_snapshot` | false / true | true / false | Practice tears down often |

Read replicas are out of scope: the app uses a single pool.

## Releasing

Terraform manages infrastructure, and a release is just a new `app_version`.

`infra/scripts/release.sh`:
1. Refuse to run with uncommitted changes. `VERSION=$(git rev-parse --short HEAD)`.
2. `npm ci && npm run build`.
3. Package `dist/`, `migrations/`, `package.json`, `package-lock.json` and `.node-version` into `url-shortener-$VERSION.tgz`.
4. `aws s3 cp` it to `s3://<bucket>/releases/` (bucket name from `terraform output`).
5. Print `terraform apply -var app_version=$VERSION`.

Applying a new `app_version` changes the launch template user data, so the ASG's instance refresh replaces instances one at a time without dropping capacity.

## Boot sequence (`user_data.sh.tftpl`)

1. Install Node from the official arm64 tarball at the version in the release's `.node-version`. AL2023's packaged Node is older than 26.
2. Download and unpack the release from S3; `npm ci --omit=dev`.
3. Download the RDS CA bundle (`https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem`).
4. Read the DB password from SSM. Write `/etc/url-shortener.env` (mode 600) with `PORT=3000`, `BASE_URL`, `DATABASE_URL=postgres://...@<endpoint>:5432/urlshortener?sslmode=verify-full` and `NODE_EXTRA_CA_CERTS=<bundle>`. RDS Postgres 16 forces SSL by default, and its CA isn't in Node's trust store.
5. `node dist/migrate.js` (needs the app change below).
6. Start a systemd unit running `node dist/server.js` as a non-root user, with `Restart=always`, `EnvironmentFile=` and `KillSignal=SIGTERM`.

## Small app changes (same PR)

1. **Migrations safe to run from several instances at once.** Instances booting together would race in `src/migrate.ts`. Take `pg_advisory_lock(<constant>)` on a dedicated client before reading `schema_migrations`, and release it at the end.
2. **Graceful shutdown.** In `src/server.ts`, on `SIGTERM` stop accepting connections, let in-flight requests finish, close the pool, then exit. This keeps instance refresh and scale-in from dropping requests (the NLB deregistration delay is 30 s).
3. **`.env.example` / README:** mention that production sets these values via `infra/`.

## Cost (on-demand us-east-1; check with the AWS Pricing Calculator)

Practice, always on, $/hour:
- NLB 0.0225 + ~1 capacity unit 0.006 + 2 IPv4 × 0.005 ≈ 0.039
- EC2 t4g.micro 0.0084 + IPv4 0.005 + 8 GB disk 0.001 ≈ 0.014
- RDS db.t4g.micro 0.016 + 20 GB storage 0.003 ≈ 0.019
- **≈ $0.07/hour ≈ $52/month.** At 10 practice hours a week with `terraform destroy` in between, it's a few dollars a month.

Full scale: ≈ $4,000/month. Data transfer out ~$2,660 (30 TB at ~1 KB/redirect), NLB ~$290, RDS ~$630, servers ~$370, IPv4 ~$40. Don't send per-request logs to CloudWatch: 200 GB/day × $0.50/GB ≈ $3,000/month.

## Verification

In the implementing session (no AWS credentials expected):
- `terraform fmt -check -recursive infra` and `terraform -chdir=infra init -backend=false && terraform -chdir=infra validate`. If the Terraform registry is blocked by the network policy, ask for access instead of skipping.
- `bash -n` on the scripts and the rendered user data; `shellcheck` if available.
- `npm run build && npm test` for the app changes. Add a test that runs two migrators at once and expects both to succeed.

By the user, in their AWS account:
1. `cp terraform.tfvars.example terraform.tfvars`, set `budget_alert_email`.
2. `terraform apply` with an initial release (`release.sh`, then `apply -var app_version=...`).
3. `curl http://<nlb>/health` returns 200; `POST /api/urls` returns 201 with a `shortUrl` on the NLB host; `GET` it returns 302.
4. Release a second version and watch the instance refresh complete with `/health` staying up (`while true; do curl -s -o /dev/null -w '%{http_code}\n' .../health; sleep 1; done`).
5. `aws autoscaling set-desired-capacity --desired-capacity 2` and check that both targets go healthy in the target group.
6. `terraform destroy`, then check in the console that nothing is left (EIPs, snapshots, the S3 bucket).

## Out of scope

CI/CD, a remote state backend, read replicas, in-process redirect cache, WAF/rate limiting, monitoring dashboards. These are good follow-ups.
