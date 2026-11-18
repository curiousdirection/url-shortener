import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

// The CloudFront Function is plain JavaScript with no exports, so load it as text.
const source = readFileSync(new URL("../infra/app/functions/forwarded-host.js", import.meta.url), "utf8");
const handler = new Function(`${source}\nreturn handler;`)() as (event: unknown) => {
  headers: Record<string, { value: string }>;
};

const run = (headers: Record<string, { value: string }>) => handler({ request: { headers } }).headers;

describe("forwarded-host CloudFront Function", () => {
  it("copies the viewer's Host into x-forwarded-host", () => {
    expect(run({ host: { value: "d111.cloudfront.net" } })["x-forwarded-host"]).toEqual({ value: "d111.cloudfront.net" });
  });

  it("overwrites a value the viewer sent", () => {
    const headers = run({ host: { value: "d111.cloudfront.net" }, "x-forwarded-host": { value: "evil.com" } });
    expect(headers["x-forwarded-host"].value).toBe("d111.cloudfront.net");
  });

  it("removes the header when there is no Host", () => {
    expect(run({ "x-forwarded-host": { value: "evil.com" } })).not.toHaveProperty("x-forwarded-host");
  });
});
