import { describe, expect, it } from "vitest";
import { handler } from "../src/lambda.js";

// A Lambda function URL event (payload format 2.0), cut down to
// what Hono reads.
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
});
