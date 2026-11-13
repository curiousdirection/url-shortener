import pg from "pg";
import { config } from "./config.js";

// Deployed, infra/app.tf sets PGHOST, PGUSER, PGPASSWORD, PGDATABASE and PGSSLMODE, which pg
// reads itself. Locally there are none, so DATABASE_URL is used.
export const createPool = () =>
  new pg.Pool(process.env.PGHOST ? {} : { connectionString: config.databaseUrl });
