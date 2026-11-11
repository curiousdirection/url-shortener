import { createPool } from "./db.js";
import { runMigrations } from "./migrations.js";

const pool = createPool();
try {
  await runMigrations(pool);
} finally {
  await pool.end();
}
