import { type ChildProcess, spawn } from "node:child_process";
import { once } from "node:events";
import { createServer } from "node:net";
import pg from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { config } from "../src/config.js";
import { runMigrations } from "../src/migrator.js";

// Throwaway database so locking `urls` can't disturb the other test files.
const dbName = "urlshortener_shutdown_test";
const withDb = (name: string) => {
  const url = new URL(config.databaseUrl);
  url.pathname = `/${name}`;
  return url.toString();
};

const admin = new pg.Pool({ connectionString: config.databaseUrl });
let pool: pg.Pool;
let child: ChildProcess | undefined;

beforeAll(async () => {
  await admin.query(`DROP DATABASE IF EXISTS ${dbName}`);
  await admin.query(`CREATE DATABASE ${dbName}`);
  pool = new pg.Pool({ connectionString: withDb(dbName) });
  await runMigrations(pool);
});
afterAll(async () => {
  child?.kill("SIGKILL");
  await pool?.end();
  await admin.query(`DROP DATABASE IF EXISTS ${dbName}`);
  await admin.end();
});

const freePort = () =>
  new Promise<number>((resolve) => {
    const s = createServer().listen(0, () => {
      const { port } = s.address() as { port: number };
      s.close(() => resolve(port));
    });
  });

describe("graceful shutdown", () => {
  it("finishes an in-flight request on SIGTERM, then exits 0", async () => {
    const port = await freePort();
    child = spawn(process.execPath, ["--import", "tsx", "src/server.ts"], {
      env: { ...process.env, PORT: String(port), DATABASE_URL: withDb(dbName) },
      stdio: ["ignore", "pipe", "inherit"],
    });
    await new Promise<void>((resolve) => {
      child!.stdout!.on("data", (d) => String(d).includes("listening") && resolve());
    });
    const exited = once(child, "exit");

    // Block the request's SELECT on a table lock so it is still in flight when SIGTERM arrives.
    const lock = await pool.connect();
    await lock.query("BEGIN");
    await lock.query("LOCK TABLE urls IN ACCESS EXCLUSIVE MODE");
    const response = fetch(`http://127.0.0.1:${port}/nosuchcode`, { redirect: "manual" });
    for (;;) {
      const { rowCount } = await pool.query(
        "SELECT 1 FROM pg_stat_activity WHERE datname = $1 AND wait_event_type = 'Lock'",
        [dbName],
      );
      if (rowCount) break;
      await new Promise((r) => setTimeout(r, 20));
    }

    child.kill("SIGTERM");
    const early = await Promise.race([exited, new Promise((r) => setTimeout(() => r("still running"), 300))]);
    expect(early).toBe("still running");

    await lock.query("COMMIT");
    lock.release();

    expect((await response).status).toBe(404);
    const [code] = await exited;
    expect(code).toBe(0);
  });
});
