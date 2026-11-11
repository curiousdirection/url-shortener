import { describe, expect, it } from "vitest";
import { createRoutes } from "../src/http/handlers.js";
import type { Route } from "../src/http/types.js";
import { AliasTakenError, type UrlService } from "../src/urlService.js";

// In-memory service: handlers are tested without Hono, HTTP, Postgres or Redis.
function fakeService(): UrlService {
  const store = new Map<string, string>();
  let n = 0;
  return {
    async create(longUrl, alias) {
      const code = alias ?? `gen${++n}`;
      if (store.has(code)) throw new AliasTakenError(code);
      store.set(code, longUrl);
      return code;
    },
    async resolve(code) {
      return store.get(code) ?? null;
    },
  };
}

function setup() {
  const routes = createRoutes(fakeService(), "http://short.test");
  const find = (method: Route["method"], path: string) => routes.find((r) => r.method === method && r.path === path)!.handler;
  return {
    create: find("POST", "/api/urls"),
    redirect: find("GET", "/:code"),
    health: find("GET", "/health"),
  };
}

describe("handlers", () => {
  it("creates a short url", async () => {
    const { create } = setup();
    const res = await create({ params: {}, body: { url: "https://example.com" } });
    expect(res).toEqual({
      status: 201,
      body: { code: "gen1", shortUrl: "http://short.test/gen1", longUrl: "https://example.com" },
    });
  });

  it("returns 409 for a taken alias", async () => {
    const { create } = setup();
    await create({ params: {}, body: { url: "https://a.com", alias: "mine" } });
    const res = await create({ params: {}, body: { url: "https://b.com", alias: "mine" } });
    expect(res.status).toBe(409);
  });

  it("returns 400 with issues for invalid input", async () => {
    const { create } = setup();
    for (const body of [undefined, {}, { url: "nope" }, { url: "ftp://x.com" }, { url: "https://x.com", alias: "api" }]) {
      const res = await create({ params: {}, body });
      expect(res.status).toBe(400);
      expect(res.body).toMatchObject({ error: "invalid request" });
    }
  });

  it("redirects known codes and 404s unknown ones", async () => {
    const { create, redirect } = setup();
    await create({ params: {}, body: { url: "https://example.com/x", alias: "abc" } });
    expect(await redirect({ params: { code: "abc" } })).toEqual({
      status: 302,
      headers: { location: "https://example.com/x" },
    });
    expect((await redirect({ params: { code: "zzz" } })).status).toBe(404);
  });

  it("reports health", async () => {
    expect(await setup().health({ params: {} })).toEqual({ status: 200, body: { status: "ok" } });
  });
});
