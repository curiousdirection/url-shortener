import type { Pool } from "pg";
import { encode } from "./base62.js";

// Offset so generated codes start at 6 characters.
const OFFSET = 62 ** 5;

export interface CodeGenerator {
  next(): Promise<string>;
}

export function createCodeGenerator(pool: Pool): CodeGenerator {
  return {
    async next() {
      const { rows } = await pool.query("SELECT nextval('url_code_seq') AS n");
      // pg returns int8 as a string.
      return encode(OFFSET + Number(rows[0].n));
    },
  };
}
