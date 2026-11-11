import { createHash } from "node:crypto";
import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { createPool } from "./db.js";

const dir = join(import.meta.dirname, "..", "migrations");
const pool = createPool();

await pool.query(
  `CREATE TABLE IF NOT EXISTS schema_migrations (
    name        TEXT PRIMARY KEY,
    checksum    TEXT NOT NULL,
    applied_at  TIMESTAMPTZ NOT NULL DEFAULT now()
  )`,
);
const applied = new Map<string, string>(
  (await pool.query("SELECT name, checksum FROM schema_migrations")).rows.map((r) => [r.name, r.checksum]),
);

for (const file of (await readdir(dir)).filter((f) => f.endsWith(".sql")).sort()) {
  const sql = await readFile(join(dir, file), "utf8");
  const checksum = createHash("sha256").update(sql).digest("hex");

  if (applied.has(file)) {
    if (applied.get(file) !== checksum) {
      throw new Error(`${file} was modified after being applied; add a new migration instead`);
    }
    continue;
  }

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(sql);
    await client.query("INSERT INTO schema_migrations (name, checksum) VALUES ($1, $2)", [file, checksum]);
    await client.query("COMMIT");
    console.log(`applied ${file}`);
  } catch (e) {
    await client.query("ROLLBACK");
    throw e;
  } finally {
    client.release();
  }
}
await pool.end();
