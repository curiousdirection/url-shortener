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

Tests use a separate Postgres (`postgres-test`, port 5433, RAM-backed so it is wiped on restart) and Redis DB 1, configured in `.env.test`, because they truncate tables. Vitest refuses to run if the database name doesn't end in `_test`.

```bash
docker compose up -d
npm run migrate:test
npm test
```
