# URL Shortener

Node + TypeScript + Hono + Postgres. Short codes come from a Redis counter (`INCR url:counter`), base62-encoded and offset so codes are at least 6 characters.

## Run

```bash
docker compose up -d
cp .env.example .env
npm install
npm run migrate
npm run dev
```

## API

- `POST /api/urls` with `{ "url": "https://...", "alias": "optional-alias" }` returns `201 { code, shortUrl, longUrl }`. `400` on invalid input, `409` if the alias is taken.
- `GET /:code` redirects (302) to the original URL, or `404`.
- `GET /health`

Example:

```bash
curl -X POST http://localhost:3000/api/urls \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com/some/very/long/path", "alias": "my-link"}'
```

```json
{"code":"my-link","shortUrl":"http://localhost:3000/my-link","longUrl":"https://example.com/some/very/long/path"}
```

Leave out `alias` to get a generated code. Then open `http://localhost:3000/my-link` (or `curl -i` it) to be redirected.

## Test

Tests use a separate Postgres (`postgres-test`, port 5433) and Redis (`redis-test`, port 6380), both RAM-only so they are wiped on restart, configured in `.env.test`, because they truncate tables. Vitest refuses to run if the database name doesn't end in `_test`.

```bash
docker compose up -d
npm run migrate:test
npm test
```

## Assumptions

This is a design exercise. Design decisions (code length, storage, caching) are sized against the scale below, but the app runs on free or near-free infrastructure, so the deployed version isn't expected to handle that load.

- Some links point to private content, so codes must not be guessable.
- Up to 1 billion stored URLs.
- 100 million daily active users.