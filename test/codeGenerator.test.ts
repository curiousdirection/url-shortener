import { describe, expect, it } from "vitest";
import { generateCode } from "../src/codeGenerator.js";

describe("generateCode", () => {
  it("returns 7 base62 characters", () => {
    for (let i = 0; i < 100; i++) expect(generateCode()).toMatch(/^[0-9a-zA-Z]{7}$/);
  });

  it("does not repeat", () => {
    const codes = new Set(Array.from({ length: 1000 }, generateCode));
    expect(codes.size).toBe(1000);
  });
});
