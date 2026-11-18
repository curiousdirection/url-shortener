# 7. Put CloudFront in front of the function

Date: 2026-11-18. Status: accepted.

## Context

[0006](0006-move-to-lambda-and-dynamodb.md) assumes a CDN caches most redirects. The CDN has to call the function by its AWS hostname, and the function should accept nothing else.

## Decision

- **CloudFront, in the app stack,** at its free `*.cloudfront.net` address.
- **Only CloudFront can call the function.** The function URL requires signed calls, CloudFront signs them, and the function allows only this distribution.
- **Caching:** redirects for a day, 404s for 10 seconds. `/api/*` and `/health` aren't cached.
- **Rate limits per IP (AWS WAF), at full scale only:** 1,000 requests and 20 link creations per 5 minutes.
- **Pay as you go.** Free Tier accounts can't use CloudFront's flat-rate plans ([plans](https://docs.aws.amazon.com/PricingPlanManager/latest/UserGuide/plans.html)).
- **No other cache and no API Gateway.**

How to run it is in [infra/README.md](../../infra/README.md).

## Why

- **It can call the function directly and sign the request.** Cloudflare can only on Enterprise; below that it needs API Gateway, about $3k a month more at full scale.
- **Its price is published.** Cloudflare's full-scale price needs a quote.
- **Same AWS account and Terraform,** and a free address.
- **About $0 for practice.** CloudFront's free tier covers it, and WAF (about $7 a month even when idle) is off.

## Consequences

- **Full scale costs about $39,000 a month for CloudFront and $18,000 for WAF** ("Cost" in [infra/README.md](../../infra/README.md)). Cloudflare doesn't charge for cache hits, so it might be cheaper; that needs a quote.
- **The 90% cache-hit figure from [0006](0006-move-to-lambda-and-dynamodb.md) is still a guess.**
- **Creating a link needs a body hash** (`x-amz-content-sha256`), because CloudFront's signature has to cover the body ([README](../../README.md#api)).
- **Taking down a link needs a cache invalidation.**
- **Rate limits are per IP,** so a flood from many IPs gets through. CloudFront's DDoS protection and the cache handle that.
- **Practice doesn't exercise the rate limits** unless they're switched on.

## Alternatives considered

- **Cloudflare:** see Why.
- **API Gateway in front of the function:** a fee per request, and not needed with CloudFront.
- **An in-process cache or Redis:** each instance would cache separately, and a hit still starts the function.

## Revisit when

Cloudflare's full-scale price is known, the real cache hit rate is known, or the traffic doesn't fit per-request pricing.
