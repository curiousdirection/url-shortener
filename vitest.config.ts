import { readFileSync } from "node:fs";
import { parseEnv } from "node:util";
import { defineConfig } from "vitest/config";

const env = parseEnv(readFileSync(".env.test", "utf8"));

// Tests TRUNCATE tables, so never let them point at a non-test database.
const dbName = new URL(env.DATABASE_URL ?? "").pathname.slice(1);
if (!dbName.endsWith("_test")) {
  throw new Error(`Refusing to run tests against "${dbName}": DATABASE_URL in .env.test must end in _test`);
}

export default defineConfig({ test: { env } });
