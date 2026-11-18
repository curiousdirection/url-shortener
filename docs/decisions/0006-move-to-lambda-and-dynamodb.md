# 6. Move to Lambda and DynamoDB

Date: 2026-11-18. Status: accepted; supersedes [0001](0001-run-migrations-on-every-instance.md), [0002](0002-deploy-with-ecs-express-mode.md) and [0005](0005-postgres-sequence-for-short-codes.md), and the database password in [0003](0003-split-stacks-remote-state-and-ci-deploys.md).

**This assumes a CDN will cache redirects at full scale.** Which CDN is a later ADR.

## Context

The app ran on ECS Express Mode with RDS Postgres ([0002](0002-deploy-with-ecs-express-mode.md)). The practice deployment cost about $50 a month, and the stack needed a VPC, a database password and migrations. The app does one lookup by key per redirect and one write per new link.

## Decision

- **A Lambda function with a function URL** (a zip, on Arm). Hono's `hono/aws-lambda` adapter handles the Lambda events. The function URL is the public address for now.
- **DynamoDB for the links:** one on-demand table, key `code`.
- **Random 7-character codes,** written only if the code is free. On a collision, draw again, up to 5 times. A taken alias returns `409`.
- **On a miss, read again with a strongly consistent read,** so a link created a moment ago doesn't return `404`.
- **Node.js 24.** Lambda's Node.js 26 runtime is still a preview.

How to run it is in [infra/README.md](../../infra/README.md).

## Why

- **Practice drops from about $50 a month to about $0.** Nothing bills while idle.
- **Less to run:** no VPC, database password, migrations or container image.
- **Behind a CDN, full scale costs about the same.** Only cache misses reach the function. At 90% cache hits (a guess), the origin costs about $1.2k a month, against $0.6–0.9k on ECS and RDS.
- **No API Gateway needed.** The function URL is free.

## Consequences

- **Without a CDN, full scale costs about twice the old stack,** because Lambda charges per request ("Cost" in [infra/README.md](../../infra/README.md)). Until the CDN is added, only the practice deployment makes sense.
- **The CDN must be able to call the function by its AWS hostname.** CloudFront can. Cloudflare below Enterprise can't, and would need API Gateway, about $3k a month more at full scale.
- **Without a CDN, spikes aren't absorbed.** DynamoDB limits reads of a single key, and Lambda adds at most 1,000 instances every 10 seconds.
- **Codes rarely collide.** There are about 3.5 trillion 7-character codes. With 1 billion links stored, a new code is taken about 1 time in 3,500, and the create draws again. Five collisions in a row, which fails the create, is about 1 in 10¹⁸.
- **Cold starts.** A request that needs a new copy of the function waits a few hundred milliseconds while it starts. That's common at practice size, and rare at full scale behind a CDN.
- **The function URL is public until the CDN is added** ([docs/security.md](../security.md)).

## Alternatives considered

- **Stay on ECS and RDS:** cheaper without a CDN, but about $50 a month for practice and more to run.
- **Lambda Web Functions:** run the Node server as is, but are newer and capped at 10,000 requests a second per endpoint.
- **API Gateway in front of Lambda:** a fee per request and not needed with a function URL.

## Revisit when

The CDN is chosen, or the real cache hit rate is known.
