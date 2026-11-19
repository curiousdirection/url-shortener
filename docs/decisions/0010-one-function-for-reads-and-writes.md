# 10. Keep one function for redirects and creates

Date: 2026-11-19. Status: accepted; follows [0006](0006-move-to-lambda-and-dynamodb.md) and [0007](0007-cdn-cloudfront.md).

## Context

One Lambda function serves both redirects (`GET /:code`) and creates (`POST /api/urls`). It could be split into a redirect function and a create function, each with its own role, function URL and CloudFront origin.

## Decision

Keep one function. Split it when one of the conditions under "Revisit when" is met.

## Why

- **CloudFront already separates the traffic.** Most redirects are answered from its cache and never reach the function, and `/api/*` has its own behaviour (`infra/app/cdn.tf`). The function sees creates and redirect cache misses, which are both low-volume.
- **Fewer cold starts at practice size.** Practice traffic is mostly creating a link and then opening it. One warm copy serves both. Two functions would each need a copy, so both requests would cold start ([0006](0006-move-to-lambda-and-dynamodb.md) has the cold-start times).
- **Little gain in permissions.** The role has only `GetItem` and `PutItem` on one table (`infra/foundation/iam.tf`). Splitting would take `PutItem` from the redirect path, but both paths are public and validated alike, so neither is the likelier one to be compromised.
- **Little gain in start-up time.** The redirect path wouldn't load zod. Most of the start-up time is setting up the AWS SDK and its connection to DynamoDB, which both paths need.
- **Less to run.** A split needs a second function, function URL, log group, role, origin and permissions. CI can't create these ([docs/security.md](../security.md)), so a person would apply them, and releases and rollbacks would cover two functions.

## Consequences

- **A burst of redirect cache misses can throttle creates.** Both share the function's copies and the account's concurrency limit. Only a separate create function with reserved concurrency would guarantee creates capacity. Lambda reserves only what leaves at least 100 unreserved ([concurrency](https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html)), so this needs an account limit above 100.
- **Redirects and creates share one set of metrics.** The function's errors, duration and throttles aren't split by route.

## Alternatives considered

- **One function per route,** sharing one zip with two handlers: see Why.
- **Reserved concurrency on the one function:** it caps both routes together, so it can't keep room for creates.

## Revisit when

- **Creates are throttled during redirect spikes** (the function's `Throttles` metric rises during a spike, and creates get `429`). Split, and reserve concurrency for creates.
- **The create path gets heavier,** for example a URL blocklist or Safe Browsing check (the abuse gap in [docs/security.md](../security.md)), sign-in, or a secret. A split keeps that code, its dependencies and its secret off the redirect path and out of its role.
