# 9. Serve the web page from S3, behind the same CloudFront distribution

Date: 2026-11-19. Status: accepted; follows [0007](0007-cdn-cloudfront.md).

## Context

Creating a link needs a hand-made body hash for `x-amz-content-sha256` ([0007](0007-cdn-cloudfront.md)). We want a page that does it. There is no custom domain, so the page has to be on the same `*.cloudfront.net` address as the API and the short links, or the browser would treat the API as another site.

## Decision

- **A private S3 bucket as a second origin of the existing distribution.** Only this distribution may read it, through an origin access control (OAC), like the function.
- **Vite and plain TypeScript, no framework.** The page is a form, a result and a copy button.
- **Routing:** the default behaviour stays on the function (redirects). `/index.html` and `/assets/*` go to the bucket, and `default_root_object` is `index.html`.
- **Caching:** the files in `/assets` have hashed names and are cached for a year. `index.html` is cached at the edge for a year too, and each release clears it. Browsers don't keep it, so a visitor never loads an old page. CI can clear it because the deploy role may create invalidations.
- **The page deploys apart from the function,** after it, and only when something in it changed.

## Why

- **Not served by the function.** The page releases apart from the function, so a page change never redeploys it and a bad function release can't change the page. A cache miss on the page needs no cold start, and `/assets/*` doesn't have to share the function's `/:code` paths.
- **Not a separate host.** The API and the page on one address need no CORS and no second certificate.
- **The edge cache absorbs the traffic.** Assets are hit once per edge location, and `index.html` until the next release.

## Consequences

- **`/` may not reach the bucket.** The CloudFront docs don't say whether `/` is turned into `/index.html` before or after CloudFront picks the behaviour. If it is before, `/` is served from the bucket. If it is after, `/` matches the default behaviour and the function answers `404`. Check on the first release: `curl $url/` must return the HTML.
- **Fallback, only if that check fails:** a viewer-request CloudFront Function on the default behaviour that sends `/` to the bucket (`cf.selectRequestOriginById`). It would run on every redirect. CloudFront Functions cost $0.10 per million invocations, so at about 30 billion requests a month that is about $3,000 a month. Not built.
- **`assets` is a reserved alias,** because `/assets/*` can't reach the function.
- **A public form makes abuse easier.** Creating a link no longer needs a hash by hand ([docs/security.md](../security.md)).
- **CI can upload to the bucket and clear the cache, but not create or delete the bucket,** like the other resources, so the first release is run by hand.

## Alternatives considered

- **Serve the page from the function:** see Why.
- **A separate host** (another distribution or the bucket's own address): the API would need CORS, and the short link would not be on the same address.
- **Short browser cache times on `index.html`:** a visitor could get an old page for minutes after a release, and the page's files change with it.
- **A framework:** more to build and keep updated for a form.

## Revisit when

The check of `/` fails, or the page grows past a form.
