import { createPool } from "./db.js";
import { runMigrations } from "./migrator.js";

const pool = createPool();
try {
  await runMigrations(pool);
} finally {
  await pool.end();
}
