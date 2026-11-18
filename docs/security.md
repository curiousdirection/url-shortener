# Security

What protects the app and its deployment today, and what isn't covered yet. Update this when a change adds, removes or weakens a control.

## In place

### Access to AWS

- **Stored keys, narrowly used.** GitHub Actions signs in with an IAM user's access key (a GitHub secret) and assumes a role, so jobs get credentials that expire within an hour. Each user can only assume its own role, and each role trusts only its user ([ADR 0004](decisions/0004-access-keys-instead-of-oidc.md)).
- **Deploy keys only on `main`.** They are secrets of the `production` environment, which only `main` can use. The plan keys are repository secrets, so CI on any branch can use them.
- **Least privilege for CI.** The deploy role can update the one Lambda function, its URL settings and its log group, and hand the function's role to Lambda. It can't create or delete them. The plan role is read-only and only plans `infra/app`. Neither role can change IAM or the bootstrap stack (`infra/bootstrap/deploy-role.tf`, `plan-role.tf`).
- **No secrets for branches.** The plan role is explicitly denied SSM parameter reads, Secrets Manager values and KMS decryption, except through Lambda so it can read the function's environment variables. Code pushed to a branch couldn't read a secret if one is added later, as long as secrets live in SSM or Secrets Manager and never in Lambda environment variables. The app has no secrets today.
- **Workflow permissions.** Workflows get a read-only `GITHUB_TOKEN`. The test job, which runs npm packages, is given no secrets. The deploy job builds the zip, and so runs npm packages, before it signs in to AWS.
- **Infra changes need a person.** CI never plans or applies `infra/foundation` or `infra/bootstrap`.

### The function

- **Least privilege for the app.** The function's role can only read and write items (`GetItem`, `PutItem`) in the one table, and write to its own log group (`infra/foundation/iam.tf`). It can't scan, delete or change the table.
- **No credentials in the code.** The function gets short-lived credentials from its role. The table name is its only setting.
- **No overwrites.** A link is written only if its code is free (a conditional write), so an existing link can't be replaced by creating another with the same code or alias.
- **Random codes.** Codes come from `node:crypto`, so they can't be guessed from earlier ones.
- **Quiet logs.** Only warnings and errors are logged, so requests are not written to the logs.

### Supply chain

- **Actions pinned to commit SHAs**, so a moved tag can't change what runs.
- **Locked dependencies.** `npm ci` installs exactly what `package-lock.json` says.
- **One file deployed.** The zip holds only the bundled app, not `node_modules` or the source.
- **Same zip for the same code.** The zip is built the same way every time, so the same code gives the same hash.

### Network and data

- **Encrypted connections.** Clients reach the function URL over HTTPS, and the function reaches DynamoDB over HTTPS.
- **Encrypted storage.** The table is encrypted at rest (DynamoDB always does this, with an AWS-owned key). The Terraform state bucket is encrypted (SSE-S3), versioned, blocks public access and refuses non-TLS requests.
- **Backups and delete protection** for the table are switched on at full scale (`infra/foundation/full-scale.tfvars.example`), and off for practice.
- **No network to defend.** There is no VPC, database server or open port. The only way in is the function URL.

### The app

- **Input validation.** Requests are validated with zod, and only `http:` and `https:` URLs are accepted (`src/app.ts`). A code in the path that could never exist is a `404` without a table read.
- **Safe releases.** A manual rollback is one workflow run, and the deploy checks `/health` afterwards. A release is not rolled out gradually.

## Not covered yet

| Gap | What it would catch | Typical tool |
|---|---|---|
| Public function URL | Until the CDN PR, the function URL has no authentication, so anyone can call it directly, not only through a CDN. The CDN PR will turn on `AWS_IAM` auth with origin access control, so only the CDN can call it | CloudFront origin access control |
| Rate limiting | There is no limit on requests or on creating links, so a flood is paid for by us, and Lambda can scale to the account's concurrency limit | CDN rate rules, AWS WAF, reserved concurrency |
| Dependency scanning | Known CVEs in npm packages | Dependabot alerts, `npm audit` |
| IaC scanning | Insecure Terraform (open permissions, missing encryption) | Trivy, Checkov |
| Static analysis | Injection and unsafe code patterns | CodeQL |
| Secret scanning | Keys committed by mistake | GitHub secret scanning with push protection |
| Workflow linting | Broken or unsafe GitHub Actions | actionlint, zizmor |
| Automated updates | Stale npm packages and action SHAs | Dependabot, Renovate |
| Branch protection | Unreviewed or unchecked code reaching `main` | GitHub settings: require a pull request and passing checks |
| Abuse of the shortener | Anyone can create links (no auth, no rate limit), so it can hide phishing or malware links | Rate limiting, AWS WAF, a URL blocklist |
| Key rotation | Stale or leaked CI access keys, which don't expire | A reminder to rotate by hand (`infra/README.md`), or OIDC, which this account's Free plan blocks ([ADR 0004](decisions/0004-access-keys-instead-of-oidc.md)) |
| Account monitoring | Suspicious API calls or access | CloudTrail, GuardDuty |
