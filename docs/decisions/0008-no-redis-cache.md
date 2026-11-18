# 8. Don't cache redirects in Redis

Date: 2026-11-18. Status: accepted.

## Context

A cache in front of the database is the usual way to make redirects fast and cheap, and Redis is the usual cache. The app now runs on Lambda and DynamoDB ([0006](0006-move-to-lambda-and-dynamodb.md)), behind CloudFront, which already caches redirects ([0007](0007-cdn-cloudfront.md)).

## Decision

Don't add Redis, or any other cache, between our Lambda function and DynamoDB. CloudFront is the only cache.

## Why

- **A second cache would rarely hit.** Our Lambda function only sees CloudFront's cache misses: mostly links nobody has asked for recently. A popular link reaches DynamoDB about once per cache lifetime.
- **DynamoDB is already fast enough.** Reads take single-digit milliseconds.
- **It costs money while idle.**
- **It would also need the private network (VPC) that [0006](0006-move-to-lambda-and-dynamodb.md) removed.**

## Consequences

- **DynamoDB takes every cache miss.** If the hit rate is far below the 90% guess, read costs grow with it.

## Alternatives considered

- **ElastiCache (Redis or Valkey):** see above.
- **DAX**, DynamoDB's own cache: also runs inside a VPC, with always-on nodes.
- **A cache over HTTPS** (Upstash, Momento): no VPC or idle cost, but another vendor and an API key, and it would rarely hit behind CloudFront.
- **An in-process cache in the function:** Lambda copies are short-lived and mostly see links that aren't cached anywhere yet.

## Revisit when

The real cache hit rate turns out much lower than expected and DynamoDB reads become costly or throttled.
