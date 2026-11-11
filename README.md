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

Requires Postgres and Redis running (see `.env.example`), and `npm run migrate` applied. Tests do not run migrations.

```bash
npm test
```
