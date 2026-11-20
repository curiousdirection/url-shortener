# 12. Refuse hidden and blocked link targets

Date: 2026-11-20. Status: accepted.

## Context

Anyone can create links without signing in, so the shortener can hide phishing or malware. Services that detect bad URLs either cost money (AWS WAF managed rules, which also apply only when `rate_limiting` is on) or need an API key (Google Safe Browsing).

## Decision

- **Refuse three kinds of target when a link is created**, with `400`: a URL with a username or password, a URL on the host the request came through, and a URL on a domain in `blocked_domains` (subdomains included).
- **`blocked_domains` is a Terraform variable**, passed to the function as `BLOCKED_DOMAINS`. It is empty by default.
- **Check on creation only.** Stored links and redirects are unchanged.

## Why

- **Free and no secret.** It is a few lines of code and one variable.
- **Credentials in a URL** (`https://trusted.com@evil.com`) are a common way to make a link look like it goes to another site, and almost no honest link needs them.
- **Links back at the shortener** would let someone chain redirects to hide where a link ends.

## Consequences

- **It catches only these tricks.** A phishing link on an unlisted domain, or on another shortener, still gets through. The blocklist is kept by hand.
- **Existing links aren't rechecked.** Adding a domain stops new links; an old one needs removing from the table and the CloudFront cache.
- **Later options:** Google Safe Browsing (needs an API key) and AWS WAF managed rules (cost money, and need `rate_limiting`).
