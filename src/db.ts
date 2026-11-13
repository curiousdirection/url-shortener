import pg from "pg";
import { config } from "./config.js";

// pg fills what the URL leaves out from PG* env vars (deployed, PGPASSWORD; see infra/app.tf).
export const createPool = () => new pg.Pool({ connectionString: config.databaseUrl });
