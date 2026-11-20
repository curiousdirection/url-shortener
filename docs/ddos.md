# Denial of service

What happens if someone floods the app at full scale, how we'd notice, and what we could add. None of the additions are built; the gap is listed in [security.md](security.md#not-covered-yet).

## What happens in a flood

- **Floods aimed at the network** are absorbed by AWS Shield Standard, which comes with CloudFront at no cost.
- **Popular links keep working.** CloudFront and Origin Shield answer them from the cache, so a flood of real links never reaches the function.
- **One address sending too much gets `429`** from the AWS WAF rate limits ([security.md](security.md#network-and-data)).
- **A flood of made-up codes from many addresses, each under the limit, gets through.** Every request misses the cache and reaches the function, until the function cap makes every request that misses the cache fail ([security.md](security.md#network-and-data)). That takes down new and rarely used links, and creating links.
- **Cost:** the function cap bounds Lambda and DynamoDB use. Nothing bounds what CloudFront and AWS WAF charge per request, blocked requests included.

## How we'd notice

- **The function throttles alarm** (`infra/foundation/alarms.tf`) is the only alarm a flood sets off, and only once visitors are already failing.
- **A flood the cache or the rate limits absorb sends no alarm.** CloudFront's and AWS WAF's metrics are in us-east-1, where the Free plan lets the account only read CloudWatch.
- **Who sent it:** only AWS WAF's sampled requests show this. CloudFront's access logs are off at full scale because of their cost ([infra/README.md](../infra/README.md)).

## What we could add

All but the first need the account off the Free plan.

| Addition | What it gives | Cost |
|---|---|---|
| Anomaly alarm on the function's `Invocations` | A warning before visitors fail, in the function's own region | Cents a month |
| Alarms in us-east-1: CloudFront `Requests` (anomaly detection), `4xxErrorRate` (made-up codes and `429`s), `5xxErrorRate`, and AWS WAF `BlockedRequests` per rule | A warning for floods the cache and rate limits absorb | Cents a month |
| A maximum read rate on the table (`on_demand_throughput`) | A second ceiling on DynamoDB cost; AWS treats it as a target, not a hard limit | Free |
| AWS WAF logging of blocked requests only | Who attacked: address, path, country | Only blocked requests are logged |
| A CloudFront flat-rate plan | Blocked attack traffic and requests AWS WAF blocks don't count toward the plan, AWS WAF is included, and there are no overage charges. Made-up codes pass AWS WAF, so they still count and still bill Lambda and DynamoDB. Origin Shield needs Premium, and the docs don't say whether a Lambda function URL can be the origin | $200 a month (Business) or $1,000 (Premium, allowance can be raised) for the advanced attack protection |
| AWS's managed IP reputation rule group | Blocks known botnets that the per-address limit misses | About $1 a month plus AWS WAF's per-request fee |
| A rate limit per TLS fingerprint (JA4) as well as per address | Catches many addresses running the same bot software | One more AWS WAF rule |
| AWS's managed anti-DDoS rule group | Learns normal traffic, then labels and challenges requests that look like part of a flood | Extra AWS WAF fees |
| Steps for an attack in `infra/README.md` | Where to look, and how to lower `rate_limit_all` or block addresses or countries | None |
| AWS Shield Advanced | Credits for an attack's charges, AWS's response team, automatic blocking of floods aimed at the app | About $3,000 a month with a one-year commitment; worth it only if an attack or downtime would cost more |
