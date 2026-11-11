import pg from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { config } from "../src/config.js";
import { runMigrations } from "../src/migrator.js";

// Uses its own throwaway database so it can start from an empty schema
// without disturbing the other test files running in parallel.
const dbName = "urlshortener_migrate_test";
const withDb = (name: string) => {
  const url = new URL(config.databaseUrl);
  url.pathname = `/${name}`;
  return url.toString();
};

const admin = new pg.Pool({ connectionString: config.databaseUrl });
let pool: pg.Pool;

beforeAll(async () => {
  await admin.query(`DROP DATABASE IF EXISTS ${dbName}`);
  await admin.query(`CREATE DATABASE ${dbName}`);
  pool = new pg.Pool({ connectionString: withDb(dbName) });
});
afterAll(async () => {
  await pool?.end();
  await admin.query(`DROP DATABASE IF EXISTS ${dbName}`);
  await admin.end();
});

describe("runMigrations", () => {
  it("lets several migrators run at once", async () => {
    const results = await Promise.allSettled([1, 2, 3, 4].map(() => runMigrations(pool)));
    expect(results.map((r) => r.status)).toEqual(Array(4).fill("fulfilled"));

    const { rows } = await pool.query("SELECT name FROM schema_migrations ORDER BY name");
    expect(rows.map((r) => r.name)).toEqual(["001_create_urls.sql", "002_create_url_code_seq.sql"]);
  });
});
