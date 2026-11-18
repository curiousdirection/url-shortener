# 7. Put CloudFront in front of the function

Date: 2026-11-18. Status: accepted; follows [0006](0006-move-to-lambda-and-dynamodb.md), which left the choice of CDN open.

## Context

[0006](0006-move-to-lambda-and-dynamodb.md) assumes a CDN answers most redirects from its cache, and the function URL is public until then. The CDN must be able to call the function by its AWS hostname, and the function should accept nothing else.

## Decision

- **Amazon CloudFront, in the app stack,** at its own `*.cloudfront.net` address. No custom domain or certificate.
- **The function accepts only CloudFront.** The function URL needs a signed call (`AWS_IAM`), CloudFront signs with an origin access control (OAC), and the function's policy names this one distribution.
- **Redirects are cached by the origin's headers:** a redirect for a year (links never change), a 404 for 10 seconds. `/api/*` and `/health` are never cached.
- **Rate limiting per IP with AWS WAF** on the distribution, at full scale: 1,000 requests and 20 link creations (`POST /api/*`) per 5 minutes, then `429`. It is a switch (`rate_limiting`), off for practice.
- **Pay as you go.** CloudFront's flat-rate plans would include WAF, but Free Tier accounts like this one can't use them ([plans](https://docs.aws.amazon.com/PricingPlanManager/latest/UserGuide/plans.html)). Origin Shield is a variable, off for practice.
- **No in-process cache or Redis, and no API Gateway.** The CDN is the cache.

How to run it is in [infra/README.md](../../infra/README.md).

## Why

- **Only CloudFront can call the function.** It calls a function URL by its AWS hostname and signs the request. Cloudflare can do that only on Enterprise; below that it needs API Gateway in front, about $3k a month more at full scale.
- **The price is published.** Cloudflare's full-scale price needs a sales quote.
- **Same AWS account and Terraform,** with a free `cloudfront.net` address.
- **About $0 for practice.** CloudFront's free tier covers practice traffic. WAF would cost about $7 a month even when idle, so it is off for practice.

## Consequences

- **Full scale costs more per request.** CloudFront charges per request: about $36,500 a month for about 30 billion HTTPS requests in Europe, plus about $2,500 of data transfer. With rate limits on, WAF adds about $18,000 a month ("Cost" in [infra/README.md](../../infra/README.md)). Cloudflare doesn't charge for cache hits, so it might be much cheaper, but that needs a quote.
- **The 90% cache-hit figure in [0006](0006-move-to-lambda-and-dynamodb.md) is still a guess.** It assumes Origin Shield is on, so each link misses about once rather than once per region. What settles it is how many different links get clicked per day.
- **Creating a link needs a body hash.** The function URL needs a signed body, so a client sends `x-amz-content-sha256` (the body's SHA-256 in hex) with every `POST` ([README](../../README.md#api)).
- **Taking down a link needs a cache invalidation.** Browsers don't keep redirects, so that's enough.
- **Rate limiting is per IP,** so a flood spread across many IPs still gets through. CloudFront's built-in DDoS protection and the cache handle that.
- **Practice doesn't exercise the rate limits.** Turn them on for a session to try them ("Deploy" in [infra/README.md](../../infra/README.md)).

## Alternatives considered

- **Cloudflare:** see Why. Revisit with a quote.
- **API Gateway in front of the function:** a fee per request, and not needed with CloudFront.
- **An in-process cache or Redis:** each instance would cache separately, and a hit still starts the function.

## Revisit when

Cloudflare's full-scale price is known, the real cache hit rate is known, or the traffic doesn't fit per-request pricing.
