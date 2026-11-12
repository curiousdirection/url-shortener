import { createHash } from "node:crypto";
import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import type pg from "pg";

const defaultDir = join(import.meta.dirname, "..", "migrations");

// Arbitrary constant shared by every migrator so concurrent runs queue up.
const MIGRATION_LOCK_KEY = 727_001;

// Safe to call from several processes at once: a session-level advisory lock
// makes the others wait, then find everything already applied.
export async function runMigrations(pool: pg.Pool, dir = defaultDir): Promise<void> {
  const client = await pool.connect();
  let destroyClient = false; // set if cleanup fails, so a lock can't linger on a pooled connection
  try {
    await client.query("SELECT pg_advisory_lock($1)", [MIGRATION_LOCK_KEY]);
    try {
      await client.query(
        `CREATE TABLE IF NOT EXISTS schema_migrations (
          name        TEXT PRIMARY KEY,
          checksum    TEXT NOT NULL,
          applied_at  TIMESTAMPTZ NOT NULL DEFAULT now()
        )`,
      );
      const applied = new Map<string, string>(
        (await client.query("SELECT name, checksum FROM schema_migrations")).rows.map((r) => [
          r.name,
          r.checksum,
        ]),
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

        try {
          await client.query("BEGIN");
          await client.query(sql);
          await client.query("INSERT INTO schema_migrations (name, checksum) VALUES ($1, $2)", [file, checksum]);
          await client.query("COMMIT");
          console.log(`applied ${file}`);
        } catch (e) {
          await client.query("ROLLBACK").catch(() => (destroyClient = true));
          throw e;
        }
      }
    } finally {
      await client.query("SELECT pg_advisory_unlock($1)", [MIGRATION_LOCK_KEY]).catch(() => (destroyClient = true));
    }
  } finally {
    client.release(destroyClient);
  }
}
