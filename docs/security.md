# Security

What protects the app and its deployment today, and what isn't covered yet. Update this when a change adds, removes or weakens a control.

## In place

### Access to AWS

- **Stored keys, narrowly used.** GitHub Actions signs in with an IAM user's access key (a GitHub secret) and assumes a role, so jobs get credentials that expire within an hour. Each user can only assume its own role, and each role trusts only its user ([ADR 0004](decisions/0004-access-keys-instead-of-oidc.md)).
- **Deploy keys only on `main`.** They are secrets of the `production` environment, which only `main` can use. The plan keys are repository secrets, so CI on any branch can use them.
- **Least privilege.** The deploy role can push images and update the one ECS service, and pass the app's three ECS roles to ECS. It can't run tasks or pass the database setup task's role. The plan role is read-only and only plans `infra/app`. Neither role can change IAM, the network, the database or the bootstrap stack (`infra/bootstrap/deploy-role.tf`, `plan-role.tf`).
- **No secrets for branches.** The plan role is explicitly denied SSM parameter reads, KMS decryption and Secrets Manager values, so code pushed to a branch can't read the database password.
- **Workflow permissions.** Workflows get a read-only `GITHUB_TOKEN`. The test job, which runs npm packages, is given no secrets.
- **Infra changes need a person.** CI never plans or applies `infra/foundation` or `infra/bootstrap`.

### Secrets

- **The database password is never in Terraform state, plans or logs.** It is generated as an ephemeral value and sent with write-only arguments (`infra/foundation/database.tf`).
- **Stored encrypted.** It lives in an SSM SecureString parameter. Only the execution role of the one-off database setup task may read it. That task is run by a person through `infra/scripts/release.sh`, never by CI, and the app has no password at all ([ADR 0005](decisions/0005-iam-database-authentication.md)).

### Database login

- **The app is not the master user.** It logs in as `app`, which owns the app's tables but can't create roles or databases.
- **Short-lived tokens.** The login is an IAM token valid for 15 minutes. The task role may connect only as `app` to this one database (`infra/foundation/iam.tf`).

### Supply chain

- **Actions pinned to commit SHAs**, so a moved tag can't change what runs.
- **Locked dependencies.** `npm ci` installs exactly what `package-lock.json` says.
- **Verified download.** The Dockerfile checks the RDS certificate bundle against a SHA-256 checksum.
- **Immutable image tags.** An ECR tag (the commit SHA) always means the same image.

### Network and data

- **Private database.** RDS is in private subnets, not publicly accessible, and only accepts connections from the app's security group.
- **Encrypted connections.** Clients reach the app over HTTPS through the load balancer, the only thing that can reach the tasks. The app connects to Postgres with `sslmode=verify-full`, which checks the server certificate and its name.
- **Encrypted storage.** RDS storage is encrypted. The Terraform state bucket is encrypted (SSE-S3), versioned, blocks public access and refuses non-TLS requests.

### The app

- **Input validation.** Requests are validated with zod, and only `http:` and `https:` URLs are accepted (`src/app.ts`).
- **Non-root container.** The image runs as the `node` user.
- **Safe releases.** Express Mode sends a release 5% of traffic first and rolls it back by itself if its error alarm fires. A manual rollback is one workflow run.

## Not covered yet

| Gap | What it would catch | Typical tool |
|---|---|---|
| Dependency scanning | Known CVEs in npm packages | Dependabot alerts, `npm audit` |
| Image scanning | CVEs in the OS packages and dependencies inside the image | Trivy, ECR enhanced scanning |
| IaC scanning | Insecure Terraform (open security groups, missing encryption) | Trivy, Checkov |
| Static analysis | Injection and unsafe code patterns | CodeQL |
| Secret scanning | Keys committed by mistake | GitHub secret scanning with push protection |
| Workflow linting | Broken or unsafe GitHub Actions | actionlint, zizmor |
| Automated updates | Stale npm packages and action SHAs | Dependabot, Renovate |
| Branch protection | Unreviewed or unchecked code reaching `main` | GitHub settings: require a pull request and passing checks |
| Abuse of the shortener | Anyone can create links (no auth, no rate limit), so it can hide phishing or malware links | Rate limiting, AWS WAF, a URL blocklist |
| Key rotation | Stale or leaked CI access keys, which don't expire | A reminder to rotate by hand (`infra/README.md`), or OIDC if the account allows it |
| Account monitoring | Suspicious API calls or access | CloudTrail, GuardDuty |
