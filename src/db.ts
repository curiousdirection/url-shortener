import pg from "pg";
import { config } from "./config.js";

// In AWS, DATABASE_URL has no password: it arrives separately as the secret PGPASSWORD
// (see infra/app.tf), and pg uses that for the part the URL leaves out.
export const createPool = () => new pg.Pool({ connectionString: config.databaseUrl });
