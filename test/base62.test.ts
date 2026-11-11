import { describe, expect, it } from "vitest";
import { encode } from "../src/base62.js";

describe("base62.encode", () => {
  it("encodes small values", () => {
    expect(encode(0n)).toBe("0");
    expect(encode(61n)).toBe("Z");
    expect(encode(62n)).toBe("10");
  });
  it("offset values are 6 chars", () => {
    expect(encode(62n ** 5n + 1n)).toHaveLength(6);
  });
  it("rejects negatives", () => {
    expect(() => encode(-1n)).toThrow();
  });
});
