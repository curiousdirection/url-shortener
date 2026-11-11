import { describe, expect, it } from "vitest";
import { encode } from "../src/base62.js";

describe("base62.encode", () => {
  it("encodes small values", () => {
    expect(encode(0)).toBe("0");
    expect(encode(61)).toBe("Z");
    expect(encode(62)).toBe("10");
  });
  it("offset values are 6 chars", () => {
    expect(encode(62 ** 5 + 1)).toHaveLength(6);
  });
  it("rejects negatives", () => {
    expect(() => encode(-1)).toThrow();
  });
});
