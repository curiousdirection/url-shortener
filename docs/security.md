# Security

What protects the app and its deployment today, and what isn't covered yet. Update this when a change adds, removes or weakens a control.

## In place

### Access to AWS

- **No stored keys.** The deploy job runs on a CodeBuild-hosted runner in this account and gets short-lived credentials from the CodeBuild project's service role. There are no IAM users or access keys, and no AWS secrets in GitHub ([ADR 0011](decisions/0011-deploy-on-a-codebuild-runner.md)).
- **One way to the deploy role.** Its trust policy allows only CodeBuild, and only for the runner project in this account (`aws:SourceAccount` and `aws:SourceArn`). The runner's own permissions are writing its build logs and using the GitHub connection (`infra/bootstrap/deploy-role.tf`, `infra/bootstrap/runner.tf`).
- **Least privilege for CI.** The deploy role can update, not create or delete, the function, its URL and log group, the web bucket, the CloudFront distribution, its access logs and the web ACL, and pass the function's role to Lambda. It can upload files to the web bucket but not delete them, and clear the distribution's cache. It can't change IAM or the bootstrap stack, which is explicitly denied.
- **Workflow permissions.** Workflows get a read-only `GITHUB_TOKEN`. The test job and CI's build job, which run npm packages, run on GitHub-hosted runners with no AWS credentials. The deploy job, which has them, runs no npm packages: it gets the built zip and page as artifacts.
- **Infra changes need a person.** CI never applies `infra/foundation` or `infra/bootstrap`.
- **Fork pull requests can't claim the runner.** The repository is public, and a fork's PR runs its own workflow files, so it could add a workflow named "CI" that asks for the runner. The primary control is the GitHub setting "Require approval for all external contributors" (Settings > Actions > General), so no such run starts without a person approving it. Before approving one, check that it doesn't change `.github/workflows/`.
- **Known gap: any branch can claim the runner.** CodeBuild can filter runner jobs only by workflow name, not by branch. So a workflow named "CI" on any branch could get the deploy role, which means anyone with write access can. They could change `main` anyway, so this adds little. `environment: production` is only GitHub's deployment history, not a limit.

### The function

- **Least privilege for the app.** The function's role can only read and write items (`GetItem`, `PutItem`) in the one table, and write to its own log group (`infra/foundation/iam.tf`). It can't scan, delete or change the table.
- **No credentials in the code.** The function gets short-lived credentials from its role. The table name is its only setting.
- **No overwrites.** A link is written only if its code is free (a conditional write), so an existing link can't be replaced by creating another with the same code or alias.
- **Random codes.** Codes come from `node:crypto`, so they can't be guessed from earlier ones.
- **Nothing in the logs identifies a visitor.** The app doesn't log requests. Lambda's own per-request lines hold only ids and timings. CloudFront's access logs (`cdn_access_logs`, off at full scale) hold each request's time, path, status, edge location and timings. They are deleted after 7 days.

### Supply chain

- **Actions pinned to commit SHAs**, so a moved tag can't change what runs.
- **Workflows are linted.** CI runs actionlint (broken workflows) and zizmor (unsafe ones, such as injectable expressions, broad permissions and unpinned actions) on every push, and a finding fails the build (`.github/workflows/lint.yml`). Checkouts don't leave the `GITHUB_TOKEN` in `.git`, so a later step or artifact can't leak it.
- **Locked dependencies.** `npm ci` installs exactly what `package-lock.json` says.
- **One file deployed.** The zip holds only the bundled app, not `node_modules` or the source.
- **Same zip for the same code.** The zip is built the same way every time, so the same code gives the same hash.

### Network and data

- **The web bucket is private.** It blocks public access, and its policy lets only this distribution read it (`infra/app/web.tf`).
- **Only CloudFront can call the function.** The function URL requires signed calls, and only this distribution may make them (`infra/app/main.tf`, `cdn.tf`). So the app can trust the `X-Forwarded-Host` that CloudFront sets.
- **Security headers on every response.** CloudFront adds AWS's managed security headers policy (`infra/app/cdn.tf`): `Strict-Transport-Security: max-age=31536000`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: SAMEORIGIN`, `Referrer-Policy: strict-origin-when-cross-origin` and `X-XSS-Protection: 1; mode=block`. Only `nosniff` replaces a header the origin sends; for the others the origin's own value wins. There is no Content-Security-Policy.
- **Rate limits per IP, at full scale** (`rate_limiting`, off for practice). AWS WAF answers `429` after 1,000 requests or 20 link creations in 5 minutes (`infra/app/waf.tf`). A flood from many IPs still gets through; CloudFront's DDoS protection and the cache absorb it.
- **A cap on the function.** At most 10 copies of the function run at once for practice, the account's Lambda limit, and `reserved_concurrency` copies at full scale (`infra/app/variables.tf`), so a flood of made-up codes, which all miss the cache, can't run up Lambda and DynamoDB use without limit. Past the cap, every visitor whose request misses the cache gets an error.
- **Encrypted connections.** Clients reach CloudFront over HTTPS (`/api/*` refuses plain HTTP), CloudFront reaches the function URL over HTTPS, and the function reaches DynamoDB over HTTPS.
- **Encrypted storage.** The table is encrypted at rest (DynamoDB always does this, with an AWS-owned key). The Terraform state bucket is encrypted (SSE-S3), versioned, blocks public access and refuses non-TLS requests.
- **Backups and delete protection** for the table are switched on at full scale (`infra/foundation/full-scale.tfvars.example`), and off for practice.
- **No network to defend.** There is no VPC, database server or open port. The only way in is CloudFront.

### The app

- **Input validation.** Requests are validated with zod, and only `http:` and `https:` URLs are accepted (`src/app.ts`). A code in the path that could never exist is a `404` without a table read.
- **Safe releases.** A manual rollback is one workflow run, and the deploy checks `/health` afterwards. A release is not rolled out gradually.

## Not covered yet

| Gap | What it would catch | Typical tool |
|---|---|---|
| Dependency scanning | Known CVEs in npm packages | Dependabot alerts, `npm audit` |
| IaC scanning | Insecure Terraform (open permissions, missing encryption) | Trivy, Checkov |
| Static analysis | Injection and unsafe code patterns | CodeQL |
| Secret scanning | Keys committed by mistake | GitHub secret scanning with push protection |
| Automated updates | Stale npm packages and action SHAs | Dependabot, Renovate |
| Abuse of the shortener | Anyone can create links (no auth; only the per-IP rate limit, and a public form makes it easier), so it can hide phishing or malware links | AWS WAF bot rules, a URL blocklist |
| Account monitoring | Suspicious API calls or access | CloudTrail, AWS Config (the Free plan's SCP blocks GuardDuty and Security Hub) |
