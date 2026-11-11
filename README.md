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

## Test

Tests use a separate database (`urlshortener_test`) and Redis DB 1, configured in `.env.test`, because they truncate tables. `docker compose` creates the test database on first start. Vitest refuses to run if the database name doesn't end in `_test`.

```bash
npm run migrate:test
npm test
```
