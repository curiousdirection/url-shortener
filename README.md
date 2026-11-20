# URL Shortener

Node + TypeScript + Hono, on AWS Lambda and DynamoDB. A short code is 7 random base62 characters, written only if it is free.

## Architecture

![Architecture: Client to CloudFront, which serves the web page from S3 and calls the Lambda function, which reads and writes the urls table in DynamoDB](docs/architecture.svg)

Open [`docs/architecture.html`](docs/architecture.html) in a browser for the same diagram as a page that also fits a phone screen.

- **Deployed:** CloudFront's `*.cloudfront.net` address is the public address, and it serves the web page from S3 ([ADR 0009](docs/decisions/0009-frontend-on-s3.md)). It answers repeated redirects from its cache and passes the rest to the function, which only it can call ([ADR 0007](docs/decisions/0007-cdn-cloudfront.md)). There is no server to keep running, and nothing is paid for while idle. Locally it's one Node process (`src/server.ts`) and DynamoDB Local.
- **Create:** a custom alias is written as the code. Otherwise `codeGenerator` makes a random code and writes it. The write only succeeds if the code is free: a taken alias returns `409`; a taken generated code is replaced by a new one, up to 5 times.
- **Resolve:** the table is read by its key `code`, and the app answers with a `302` redirect, or `404`. A code that isn't found is read once more, strongly consistent, so a new link never answers `404`.

## Run locally

Needs Node.js at the version in `.node-version`, and Docker for DynamoDB Local.

```bash
docker compose up -d
cp .env.example .env
npm install
npm run db:setup
npm run dev
```

For the web page, run `npm run web:dev` as well and open http://localhost:5173. It sends API calls and short links to the server on port 3000.

## Deploy

[`infra/`](infra/README.md) runs the app on AWS as a Lambda function with a function URL behind CloudFront, and the links in DynamoDB. A push to `main` that changes the app is tested, zipped and deployed by GitHub Actions (`.github/workflows/ci.yml`). The one-time setup, the manual first run and rollback are in [`infra/README.md`](infra/README.md).

What protects the app and its deployment, and what isn't covered yet: [`docs/security.md`](docs/security.md).

## API

- `POST /api/urls` with `{ "url": "https://...", "alias": "optional-alias" }` returns `201 { code, shortUrl, longUrl }`. `shortUrl` uses the address the request was sent to. `400` on invalid input, `409` if the alias is taken. On AWS the request must carry `x-amz-content-sha256`, the hex SHA-256 of the body (the function URL can't accept an unsigned body).
- `GET /:code` redirects (302) to the original URL, or `404`.
- `GET /health`
- `429` from any route: one IP sent too many requests in 5 minutes (at full scale; [limits](infra/README.md#deploy)).

The web page at `/` does this for you. From the command line:

```bash
body='{"url": "https://example.com/some/very/long/path", "alias": "my-link"}'
curl -X POST "$(terraform -chdir=infra/app output -raw url)/api/urls" \
  -H "Content-Type: application/json" \
  -H "x-amz-content-sha256: $(printf %s "$body" | openssl dgst -sha256 -hex | awk '{print $NF}')" \
  -d "$body"
```

Against the local server, use `http://localhost:3000`; it ignores the `x-amz-content-sha256` header.

## Test

Tests use a separate DynamoDB Local (`dynamodb-test`, port 8001), in memory so it is wiped on restart, configured in `.env.test`, because they empty the table. Vitest refuses to run if the table name doesn't end in `_test`.

```bash
docker compose up -d
npm run db:setup:test
npm test
```

## Assumptions

This is a design exercise. Design decisions (code length, storage, caching) are sized against the scale below, but the app runs on free or near-free infrastructure, so the deployed version isn't expected to handle that load.

- No private links
- Up to 1 billion stored URLs.
- 100 million daily active users.
- About 1 billion redirects and 10 million new links a day (on average about 11,600 and 115 per second).
- Spikes of up to 100 times that, without warning, for example when a link goes viral.