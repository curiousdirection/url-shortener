# 8. Don't cache redirects in Redis

Date: 2026-11-18. Status: accepted.

## Context

A cache in front of the database is the usual way to make redirects fast and cheap, and Redis is the usual cache. The app now runs on Lambda and DynamoDB ([0006](0006-move-to-lambda-and-dynamodb.md)), behind CloudFront, which already caches redirects ([0007](0007-cdn-cloudfront.md)).

## Decision

Don't add Redis, or any other cache, between the function and DynamoDB. CloudFront is the only cache.

## Why

- **A second cache would rarely hit.** The function only sees CloudFront's cache misses: mostly links nobody has asked for recently. A popular link reaches DynamoDB about once per cache lifetime.
- **DynamoDB is already fast enough.** Reads take single-digit milliseconds.
- **It would bring back a server we pay for all the time.** Lambda and DynamoDB only cost money when a request comes in. Redis on AWS (ElastiCache) is a server that runs day and night and is billed by the hour, even with no traffic. It can also only be reached from inside a private network (a VPC), so the function would have to move into one again.

## Consequences

- **DynamoDB takes every cache miss.** If the hit rate is far below the 90% guess, read costs grow with it.

## Alternatives considered

- **ElastiCache (Redis or Valkey):** see above.
- **DAX**, DynamoDB's own cache: also runs inside a VPC, with always-on nodes.
- **An in-process cache in the function:** Lambda copies are short-lived and mostly see links that aren't cached anywhere yet.

## Revisit when

The real cache hit rate turns out much lower than expected and DynamoDB reads become costly or throttled.
