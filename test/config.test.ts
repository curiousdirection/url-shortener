import { afterEach, expect, it, vi } from "vitest";

afterEach(() => {
  vi.unstubAllEnvs();
  vi.resetModules();
});

const loadBaseUrl = async (value: string) => {
  vi.stubEnv("BASE_URL", value);
  vi.resetModules();
  return (await import("../src/config.js")).config.baseUrl;
};

it("treats an empty BASE_URL as unset", async () => {
  expect(await loadBaseUrl("")).toBeUndefined();
});

it("uses BASE_URL when set", async () => {
  expect(await loadBaseUrl("https://sho.rt")).toBe("https://sho.rt");
});
