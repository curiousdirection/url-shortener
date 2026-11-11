import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { createCodeGenerator } from "../src/codeGenerator.js";
import { createPool } from "../src/db.js";
import { runMigrations } from "../src/migrations.js";
import { createRedis } from "../src/redis.js";
import { createUrlService } from "../src/urlService.js";

const pool = createPool();
const redis = createRedis();
const app = buildApp(createUrlService(pool, createCodeGenerator(redis)), "http://short.test");

const post = (body: unknown) =>
  app.request("/api/urls", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });

beforeAll(async () => {
  await runMigrations(pool);
});
beforeEach(async () => {
  await pool.query("TRUNCATE urls");
});
afterAll(async () => {
  await pool.end();
  redis.disconnect();
});

describe("POST /api/urls", () => {
  it("creates a generated short url and redirects", async () => {
    const res = await post({ url: "https://example.com/a/very/long/path" });
    expect(res.status).toBe(201);
    const body = await res.json();
    expect(body.code).toHaveLength(6);
    expect(body.shortUrl).toBe(`http://short.test/${body.code}`);

    const redirect = await app.request(`/${body.code}`);
    expect(redirect.status).toBe(302);
    expect(redirect.headers.get("location")).toBe("https://example.com/a/very/long/path");
  });

  it("supports a custom alias", async () => {
    const res = await post({ url: "https://example.com", alias: "my-link" });
    expect(res.status).toBe(201);
    expect((await res.json()).code).toBe("my-link");
    expect((await app.request("/my-link")).status).toBe(302);
  });

  it("returns 409 when alias is taken", async () => {
    await post({ url: "https://example.com", alias: "taken" });
    const res = await post({ url: "https://other.com", alias: "taken" });
    expect(res.status).toBe(409);
  });

  it("rejects invalid urls, bad aliases and reserved aliases", async () => {
    expect((await post({ url: "not a url" })).status).toBe(400);
    expect((await post({ url: "ftp://example.com" })).status).toBe(400);
    expect((await post({ url: "https://example.com", alias: "a!" })).status).toBe(400);
    expect((await post({ url: "https://example.com", alias: "api" })).status).toBe(400);
  });

  it("skips generated codes that collide with a custom alias", async () => {
    const first = await (await post({ url: "https://example.com" })).json();
    const next = await redis.get("url:counter");
    // Pre-claim the next code the counter will hand out.
    const { encode } = await import("../src/base62.js");
    const upcoming = encode(62 ** 5 + Number(next) + 1);
    await pool.query("INSERT INTO urls (code, long_url) VALUES ($1, 'https://claimed.com')", [upcoming]);
    const res = await post({ url: "https://example.com/2" });
    expect(res.status).toBe(201);
    const body = await res.json();
    expect(body.code).not.toBe(upcoming);
    expect(body.code).not.toBe(first.code);
  });
});

describe("GET /:code", () => {
  it("returns 404 for unknown codes", async () => {
    expect((await app.request("/nope123")).status).toBe(404);
  });
});

describe("GET /health", () => {
  it("is ok", async () => {
    expect((await app.request("/health")).status).toBe(200);
  });
});
