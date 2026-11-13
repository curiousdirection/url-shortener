import { describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import type { UrlService } from "../src/urlService.js";

// No database needed: the service is a stub.
const service: UrlService = { create: async () => "abc123", resolve: async () => null };
const create = (app: ReturnType<typeof buildApp>, url: string, headers: Record<string, string> = {}) =>
  app.request(url, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify({ url: "https://example.com" }),
  });

describe("shortUrl", () => {
  it("uses the configured base URL when there is one", async () => {
    const res = await create(buildApp(service, "https://go.example"), "http://ignored.test/api/urls");
    expect((await res.json()).shortUrl).toBe("https://go.example/abc123");
  });

  it("without a base URL, uses the request's host", async () => {
    const res = await create(buildApp(service), "http://localhost:3000/api/urls");
    expect((await res.json()).shortUrl).toBe("http://localhost:3000/abc123");
  });

  it("without a base URL, uses https when the load balancer says the client did", async () => {
    const res = await create(buildApp(service), "http://app.example.com/api/urls", {
      "x-forwarded-proto": "https",
    });
    expect((await res.json()).shortUrl).toBe("https://app.example.com/abc123");
  });

  it("ignores an X-Forwarded-Proto that is not https", async () => {
    const res = await create(buildApp(service), "http://app.example.com/api/urls", {
      "x-forwarded-proto": "javascript",
    });
    expect((await res.json()).shortUrl).toBe("http://app.example.com/abc123");
  });
});
