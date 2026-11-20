import { describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { handler, toLambdaHandler } from "../src/lambda.js";
import type { UrlService } from "../src/urlService.js";

// A Lambda function URL event (payload format 2.0), cut down to what Hono reads.
const event = (method: string, path: string) =>
  ({
    version: "2.0",
    rawPath: path,
    rawQueryString: "",
    headers: { host: "abc.lambda-url.eu-north-1.on.aws", "x-forwarded-proto": "https" },
    requestContext: { http: { method, path }, domainName: "abc.lambda-url.eu-north-1.on.aws" },
    isBase64Encoded: false,
  }) as never;

describe("Lambda handler", () => {
  it("answers a function URL request", async () => {
    const res = await handler(event("GET", "/health"), {} as never);
    expect(res).toMatchObject({ statusCode: 200, body: '{"status":"ok"}' });
  });

  it("fails the invocation when a route throws, so Lambda counts an error", async () => {
    const failing = { resolve: () => Promise.reject(new Error("boom")) } as unknown as UrlService;
    await expect(toLambdaHandler(buildApp(failing))(event("GET", "/abc1234"), {} as never)).rejects.toThrow("boom");
  });
});
