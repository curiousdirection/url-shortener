import { setupAppRole } from "./appRole.js";
import { createPool } from "./db.js";

const pool = createPool();
try {
  await setupAppRole(pool);
  console.log("app role is ready");
} finally {
  await pool.end();
}
