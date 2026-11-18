import { readFileSync } from "node:fs";
import { parseEnv } from "node:util";
import { defineConfig } from "vitest/config";

const env = parseEnv(readFileSync(".env.test", "utf8"));

// Tests empty the table, so never let them point at a real one.
if (!env.TABLE_NAME?.endsWith("_test")) {
  throw new Error(`Refusing to run tests against "${env.TABLE_NAME}": TABLE_NAME in .env.test must end in _test`);
}
if (!env.DYNAMODB_ENDPOINT) {
  throw new Error("Refusing to run tests: DYNAMODB_ENDPOINT in .env.test must point at DynamoDB Local");
}

export default defineConfig({ test: { env } });
