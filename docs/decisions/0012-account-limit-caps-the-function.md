# 12. Let the account's Lambda limit cap the function for practice

Date: 2026-11-20. Status: accepted; follows [0007](0007-cdn-cloudfront.md) and [0010](0010-one-function-for-reads-and-writes.md).

## Context

A code that isn't cached reaches the function, so anyone can keep it busy by asking for made-up codes, and the web page made the address public ([0007](0007-cdn-cloudfront.md)). We want a cap on how many copies run at once, and we wanted it to be 10, written in Terraform as the function's reserved concurrency.

Lambda only reserves concurrency that leaves at least 100 of the account's limit unreserved ([concurrency quotas](https://docs.aws.amazon.com/lambda/latest/dg/lambda-concurrency.html)). This account's limit is 10, so it can't reserve any: even a cap of 1 would make the deploy fail.

## Decision

- **For practice, the account's limit of 10 is the cap.** The function reserves nothing (`reserved_concurrency = null`).
- **At full scale, the function reserves 500** (`infra/app/full-scale.tfvars.example`), in an account whose limit is at least 600.

## Why

- **It is the same cap while this is the account's only function:** it can never run more than 10 copies at once.
- **It works now.** Reserving 10 would first need the limit raised to at least 110, a request AWS decides on and may refuse or delay.

## Consequences

- **The cap isn't in Terraform.** If the account's limit is raised, the cap rises with it and nothing in the code changes.
- **Past 10 copies, every request that misses the cache gets an error,** real visitors included.
- **A second function would share the 10.** [0010](0010-one-function-for-reads-and-writes.md) already keeps one function.

## Alternatives considered

- **Raise the limit to 110 and reserve 10:** the cap would be in Terraform, but only after AWS grants the request.
- **Rate limiting with AWS WAF:** per IP, so it doesn't cap a flood from many IPs, and it costs about $7 a month ([0007](0007-cdn-cloudfront.md)).

## Revisit when

The account's limit changes. At 110 or more, set `reserved_concurrency = 10` so the cap is back in Terraform.
