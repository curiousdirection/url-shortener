import { describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import type { UrlService } from "../src/urlService.js";

// No table needed: the service is a stub.
const service: UrlService = { create: async () => "abc123", resolve: async () => null };
const create = (app: ReturnType<typeof buildApp>, url: string, headers: Record<string, string> = {}) =>
  app.request(url, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify({ url: "https://example.com" }),
  });

describe("shortUrl", () => {
  it("uses the request's own address locally", async () => {
    const res = await create(buildApp(service), "http://localhost:3000/api/urls");
    expect((await res.json()).shortUrl).toBe("http://localhost:3000/abc123");
  });

  it("uses the address the viewer called when CloudFront forwards it", async () => {
    const res = await create(buildApp(service), "https://abc.lambda-url.eu-north-1.on.aws/api/urls", {
      "x-forwarded-host": "d111111abcdef8.cloudfront.net",
    });
    expect((await res.json()).shortUrl).toBe("https://d111111abcdef8.cloudfront.net/abc123");
  });
});
