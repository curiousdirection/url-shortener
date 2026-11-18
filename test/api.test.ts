import { PutItemCommand } from "@aws-sdk/client-dynamodb";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { generateCode } from "../src/codeGenerator.js";
import { config } from "../src/config.js";
import { createDb } from "../src/db.js";
import { createUrlService } from "../src/urlService.js";
import { createClient } from "./support/httpClient.js";
import { clearTable, prepareTable } from "./support/table.js";

const db = createDb();
const next: string[] = []; // codes the generator hands out next; when empty it is random
const app = buildApp(createUrlService(db, config.tableName, () => next.shift() ?? generateCode()));

const client = createClient(app);
const post = (body: unknown) => client.post("/api/urls", body);

beforeAll(() => prepareTable(db, config.tableName));
beforeEach(async () => {
  next.length = 0;
  await clearTable(db, config.tableName);
});
afterAll(() => db.destroy());

describe("POST /api/urls", () => {
  it("creates a generated short url and redirects", async () => {
    const res = await post({ url: "https://example.com/a/very/long/path" });
    expect(res.status).toBe(201);
    const body = await res.json();
    expect(body.code).toMatch(/^[0-9a-zA-Z]{7}$/);
    expect(body.shortUrl).toBe(`http://localhost/${body.code}`);

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
    // The first link is untouched.
    expect((await client.get("/taken")).headers.get("location")).toBe("https://example.com");
  });

  it("rejects invalid urls, bad aliases and reserved aliases", async () => {
    expect((await post({ url: "not a url" })).status).toBe(400);
    expect((await post({ url: "ftp://example.com" })).status).toBe(400);
    expect((await post({ url: "https://example.com", alias: "a!" })).status).toBe(400);
    expect((await post({ url: "https://example.com", alias: "api" })).status).toBe(400);
  });

  it("draws another code when a generated one is already taken", async () => {
    await db.send(
      new PutItemCommand({
        TableName: config.tableName,
        Item: { code: { S: "taken01" }, long_url: { S: "https://claimed.com" } },
      }),
    );
    next.push("taken01", "free002");
    const res = await post({ url: "https://example.com/2" });
    expect(res.status).toBe(201);
    expect((await res.json()).code).toBe("free002");
    expect((await client.get("/taken01")).headers.get("location")).toBe("https://claimed.com");
  });

  it("gives up after 5 taken codes", async () => {
    await post({ url: "https://example.com", alias: "same" });
    next.push(...Array(5).fill("same"));
    const res = await post({ url: "https://example.com/3" });
    expect(res.status).toBe(500);
  });
});

describe("GET /:code", () => {
  it("returns 404 for unknown codes", async () => {
    expect((await client.get("/nope123")).status).toBe(404);
  });

  it("returns 404 for a code that could never exist", async () => {
    expect((await client.get(`/${"a".repeat(3000)}`)).status).toBe(404);
  });
});

describe("GET /health", () => {
  it("is ok", async () => {
    expect((await client.get("/health")).status).toBe(200);
  });
});
