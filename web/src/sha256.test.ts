import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import { sha256Hex } from "./sha256.js";

describe("sha256Hex", () => {
  it.each(["", "abc", '{"url":"https://example.com/é?q=1","alias":"my-link"}'])("matches node:crypto for %j", async (body) => {
    expect(await sha256Hex(body)).toBe(createHash("sha256").update(body).digest("hex"));
  });
});
