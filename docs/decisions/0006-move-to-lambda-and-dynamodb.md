# 6. Move to Lambda and DynamoDB

Date: 2026-11-18. Status: accepted; supersedes [0001](0001-run-migrations-on-every-instance.md), [0002](0002-deploy-with-ecs-express-mode.md) and [0005](0005-postgres-sequence-for-short-codes.md), and the database password in [0003](0003-split-stacks-remote-state-and-ci-deploys.md).

**This decision assumes a CDN will cache redirects at full scale.** The CDN is not part of this change; it will be decided in a later ADR. Without it, Lambda costs about 2.5 times as much as the stack it replaces (see "Why"). Behind it, the two cost about the same.

## Context

The app ran on ECS Express Mode with an RDS Postgres database ([0002](0002-deploy-with-ecs-express-mode.md)). For a practice project this costs about $50 a month, mostly for the load balancer, the database and the public IPv4 addresses. It also needs a VPC, a database password, migrations that run on every start, and a container image.

The app is small: one lookup by key per redirect, and one write per new link. That fits a function and a key-value table. Redirects are the traffic that matters (about 1 billion a day, see "Assumptions" in the [README](../../README.md)), and they are the same answer for every request to a code, so a CDN can cache them.

## Decision

- **Run the app as a Lambda function with a function URL.** It is a regular Lambda function (a zip, not a container) on Arm. Hono's `hono/aws-lambda` adapter turns Lambda events into the app's normal requests. The function URL is the public address, with no authentication for now. The CDN will call it later.
- **Store links in DynamoDB.** One on-demand table, key `code`.
- **Make codes random.** Seven random base62 characters (`node:crypto`), written with a conditional `PutItem` that only succeeds if the code is free. On a collision it draws again, up to 5 times. A custom alias uses the same write; a collision returns `409`.
- **Read with a retry.** A normal read first. If the code isn't found, one more read that is strongly consistent.
- **Node.js 24.** Lambda has a Node.js 26 runtime, but it is a public preview, which AWS says not to use for production ([runtimes](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html)). So `.node-version` is 24.x, and CI and the Lambda runtime match.
- **Test against DynamoDB Local.** The Postgres service, the migrator and the migrations are removed.

How to set it up and run it is in [infra/README.md](../../infra/README.md).

## Why

- **Practice drops from about $50 a month to about $0.** Lambda and DynamoDB bill per request and have no idle cost. There is no load balancer, database server or public IPv4 address to pay for.
- **Less to run.** The VPC, the security groups, the database password and the migrations go away. There is no image to build and push.
- **At full scale, a CDN makes the cost reasonable.** Prices are on-demand `eu-north-1`, from the AWS Price List, November 2026, for the traffic in "Assumptions" (about 30 billion redirects a month):
  - *Without a CDN*, Lambda plus DynamoDB costs about 2.5 times today's roughly $6,200 a month. Lambda's request fee alone is about $6,100 a month. A load balancer costs by connection, a function by request, and nearly every redirect is its own request.
  - *Behind a CDN* that answers most redirects from its cache, only the misses reach the origin. At about 90% cache hits (a guess), the origin costs about $1.2k a month on Lambda and DynamoDB, against $0.6k to $0.9k on ECS and RDS. That is roughly the same.
- **The function URL is enough.** It is a public HTTPS address with no extra charge. API Gateway would add a fee per request and is not needed.
- **DynamoDB suits the access pattern.** A lookup by key is what it does best, and on-demand tables follow spikes without sizing.

## Consequences

- **Without the CDN, full scale costs about $15,500 a month.** This change does not add the CDN. Until it does, only the practice deployment makes sense.
- **A CDN must be able to call the function by its own AWS address.** CloudFront can (with origin access control). Cloudflare below Enterprise cannot, and would need API Gateway in front, which adds about $3k a month at full scale.
- **There are no sequence numbers.** DynamoDB has no sequence, so codes are random. Codes are 7 characters, not 6. A create occasionally retries, and the retry limit is the one in `src/urlService.ts`.
- **A normal read can miss a new link for a moment.** That is why a "not found" is read again with a strongly consistent read. A code that really doesn't exist costs two reads.
- **One very popular link can be throttled.** DynamoDB limits reads of a single key (a partition allows 3,000 read units a second). The CDN removes that load in practice; without it, a viral link could hit the limit.
- **Lambda has scaling limits.** One function adds at most 1,000 execution environments (10,000 requests a second) every 10 seconds, and the account has a concurrency limit ([scaling](https://docs.aws.amazon.com/lambda/latest/dg/scaling-behavior.html)). A 100 times spike with no cache in front would be answered with `429`.
- **The URL is public until the CDN PR.** Anyone can call the function URL directly, and there is no rate limit. See [docs/security.md](../security.md).
- **Nothing to migrate.** The foundation and app stacks were never applied, so no data or service moves. The bootstrap stack is already applied and must be applied again by hand (new CI permissions).
- **The Free plan has a spend-limit policy.** Near a spend limit, AWS denies calls to a function URL and the creation of tables and functions ([policy](https://docs.aws.amazon.com/accounts/latest/reference/scps-and-rcps-for-projects.html)).
- **Local tests no longer cover Postgres behaviour.** They cover DynamoDB Local, which is close to the real service but not the same (for example, it has no read-after-write delay, so the consistent-read retry is not exercised).

## Alternatives considered

- **Stay on ECS and RDS.** It works and costs less than Lambda without a CDN. It keeps the load balancer, the database, the VPC and the migrations, and about $50 a month at practice size.
- **Lambda Web Functions.** They run the whole Node server and can handle many requests per instance. They are newer, and an endpoint is capped at 10,000 requests a second, which cannot be raised. That is below the full-scale spike.
- **API Gateway in front of Lambda.** Not needed, because the function URL is already the front door. It would add a fee per request, about $3k a month more at full scale. It would only be needed for a CDN that can't call the function by its AWS address.

## Revisit when

The CDN is decided (this ADR assumes it), the real cache hit rate is known, or Lambda's request fee starts to matter more than running servers.
