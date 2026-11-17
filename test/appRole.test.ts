import { cpSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import pg from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { setupAppRole } from "../src/appRole.js";
import { createCodeGenerator } from "../src/codeGenerator.js";
import { config } from "../src/config.js";
import { runMigrations } from "../src/migrator.js";
import { createUrlService } from "../src/urlService.js";

// Roles are shared by the whole Postgres server, so this file uses its own database and a
// stand-in for the RDS master user, which is not a superuser: it can create roles and owns
// the database, but nothing more. It is also an admin of rds_iam, as on RDS.
const dbName = "urlshortener_approle_test";
const master = "approle_test_master";
const roles = ["app", master, "rds_iam"];

const poolFor = (user?: string, password?: string, name = dbName) => {
  const url = new URL(config.databaseUrl);
  url.pathname = `/${name}`;
  if (user) url.username = user;
  if (password) url.password = password;
  return new pg.Pool({ connectionString: url.toString() });
};

const admin = poolFor(undefined, undefined, new URL(config.databaseUrl).pathname.slice(1));
const dropAll = async () => {
  await admin.query(`DROP DATABASE IF EXISTS ${dbName} WITH (FORCE)`);
  // A role that owns things in another database can't be dropped; setup copes with it staying.
  for (const role of roles) await admin.query(`DROP ROLE IF EXISTS ${role}`).catch(() => {});
};
let asMaster: pg.Pool;
let asApp: pg.Pool;
const extraMigrations = mkdtempSync(join(tmpdir(), "migrations-"));

beforeAll(async () => {
  await dropAll();
  await admin.query("CREATE ROLE rds_iam NOLOGIN");
  await admin.query(`CREATE ROLE ${master} LOGIN PASSWORD 'master' CREATEROLE CREATEDB`);
  await admin.query(`GRANT rds_iam TO ${master} WITH ADMIN OPTION`);
  await admin.query(`CREATE DATABASE ${dbName} OWNER ${master}`);
  asMaster = poolFor(master, "master");
  // The database as the last release left it: migrated by the master user.
  await runMigrations(asMaster);
  await asMaster.query("INSERT INTO urls (code, long_url) VALUES ('old', 'https://old.example.com')");

  cpSync(new URL("../migrations", import.meta.url), extraMigrations, { recursive: true });
  writeFileSync(join(extraMigrations, "003_add_note.sql"), "ALTER TABLE urls ADD COLUMN note TEXT");
});
afterAll(async () => {
  await asMaster?.end();
  await asApp?.end();
  rmSync(extraMigrations, { recursive: true });
  await dropAll();
  await admin.end();
});

describe("setupAppRole", () => {
  it("runs twice without error", async () => {
    await setupAppRole(asMaster);
    await setupAppRole(asMaster);
  });

  it("gives the app role its tables and sequences, and no admin rights", async () => {
    const owners = await asMaster.query(
      `SELECT DISTINCT relowner::regrole::text AS owner FROM pg_class
       WHERE relnamespace = 'public'::regnamespace AND relkind IN ('r', 'S')`,
    );
    expect(owners.rows).toEqual([{ owner: "app" }]);

    const { rows } = await admin.query(
      `SELECT rolsuper, rolcreaterole, rolcreatedb, pg_has_role('app', 'rds_iam', 'member') AS iam,
              pg_has_role($1, 'app', 'usage') AS master_joined
       FROM pg_roles WHERE rolname = 'app'`,
      [master],
    );
    expect(rows[0]).toEqual({
      rolsuper: false, rolcreaterole: false, rolcreatedb: false, iam: true, master_joined: false,
    });
  });

  it("lets the app role migrate and serve requests", async () => {
    await admin.query("ALTER ROLE app PASSWORD 'app'"); // only for the test; RDS uses tokens
    asApp = poolFor("app", "app");
    // The new migration alters a table made by the master user, so this needs ownership.
    await runMigrations(asApp, extraMigrations);

    const service = createUrlService(asApp, createCodeGenerator(asApp));
    const code = await service.create("https://example.com/new");
    expect(await service.resolve(code)).toBe("https://example.com/new");
    expect(await service.resolve("old")).toBe("https://old.example.com");
  });

  it("keeps the master user working for tasks that still log in as it", async () => {
    await asMaster.query("INSERT INTO urls (code, long_url) VALUES ('m', 'https://m.example.com')");
    await asMaster.query("SELECT nextval('url_code_seq')");
    await setupAppRole(asMaster); // after the app role has made a new table, too
    expect((await asMaster.query("SELECT 1 FROM urls WHERE code = 'm'")).rowCount).toBe(1);
  });
});
