import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { encode } from "../src/base62.js";
import { createCodeGenerator } from "../src/codeGenerator.js";
import { createPool } from "../src/db.js";
import { createUrlService } from "../src/urlService.js";
import { createClient } from "./support/httpClient.js";

const pool = createPool();
const app = buildApp(createUrlService(pool, createCodeGenerator(pool)), "http://short.test");

const client = createClient(app);
const post = (body: unknown) => client.post("/api/urls", body);

beforeEach(async () => {
  await pool.query("TRUNCATE urls");
});
afterAll(async () => {
  await client.close();
  await pool.end();
});

describe("POST /api/urls", () => {
  it("creates a generated short url and redirects", async () => {
    const res = await post({ url: "https://example.com/a/very/long/path" });
    expect(res.status).toBe(201);
    const body = await res.json();
    expect(body.code).toHaveLength(6);
    expect(body.shortUrl).toBe(`http://short.test/${body.code}`);

    const redirect = await client.get(`/${body.code}`);
    expect(redirect.status).toBe(302);
    expect(redirect.headers.get("location")).toBe("https://example.com/a/very/long/path");
  });

  it("supports a custom alias", async () => {
    const res = await post({ url: "https://example.com", alias: "my-link" });
    expect(res.status).toBe(201);
    expect((await res.json()).code).toBe("my-link");
    expect((await client.get("/my-link")).status).toBe(302);
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
    const { rows } = await pool.query("SELECT nextval('url_code_seq') AS n");
    const n = Number(rows[0].n);
    // Pre-claim the code the sequence will hand out next.
    const upcoming = encode(62 ** 5 + n + 1);
    await pool.query("INSERT INTO urls (code, long_url) VALUES ($1, 'https://claimed.com')", [upcoming]);
    const res = await post({ url: "https://example.com/2" });
    expect(res.status).toBe(201);
    const body = await res.json();
    // The claimed code is skipped and the following sequence value is used.
    expect(body.code).toBe(encode(62 ** 5 + n + 2));
  });
});

describe("GET /:code", () => {
  it("returns 404 for unknown codes", async () => {
    expect((await client.get("/nope123")).status).toBe(404);
  });
});

describe("GET /health", () => {
  it("is ok", async () => {
    expect((await client.get("/health")).status).toBe(200);
  });
});
