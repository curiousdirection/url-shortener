import pg from "pg";
import { config } from "./config.js";

export const createPool = () => new pg.Pool({ connectionString: config.databaseUrl });
