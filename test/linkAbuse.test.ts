import { describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import type { UrlService } from "../src/urlService.js";

const service = { create: async () => "abc1234", resolve: async () => null } as unknown as UrlService;
const app = buildApp(service, { blockedDomains: ["blocked.example"] });

const post = (url: string, headers: Record<string, string> = {}) =>
  app.request("/api/urls", {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify({ url }),
  });

describe("POST /api/urls refuses links that can hide a destination", () => {
  it.each([
    "https://user@example.com",
    "https://user:pass@example.com",
    "http://localhost/abc",
    "http://LOCALHOST./abc",
    "https://blocked.example/x",
    "https://www.Blocked.example/x",
  ])("%s", async (url) => {
    const res = await post(url);
    expect(res.status).toBe(400);
    expect((await res.json()).error).toBeTruthy();
  });

  it("refuses the host the request came through", async () => {
    expect((await post("https://short.example/abc", { "x-forwarded-host": "short.example:443" })).status).toBe(400);
  });

  it("allows other links, including look-alike domains", async () => {
    expect((await post("https://example.com/a")).status).toBe(201);
    expect((await post("https://notblocked.example")).status).toBe(201);
  });
});
