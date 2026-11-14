import type { Pool } from "pg";
import type { CodeGenerator } from "./codeGenerator.js";

const MAX_ATTEMPTS = 5;
const UNIQUE_VIOLATION = "23505";

export class AliasTakenError extends Error {}

export interface UrlService {
  create(longUrl: string, alias?: string): Promise<string>;
  resolve(code: string): Promise<string | null>;
}

const isUniqueViolation = (e: unknown) =>
  typeof e === "object" && e !== null && (e as { code?: string }).code === UNIQUE_VIOLATION;

export function createUrlService(pool: Pool, codes: CodeGenerator): UrlService {
  console.log("test release")
  const insert = (code: string, longUrl: string) =>
    pool.query("INSERT INTO urls (code, long_url) VALUES ($1, $2)", [code, longUrl]);

  return {
    async create(longUrl, alias) {
      if (alias) {
        try {
          await insert(alias, longUrl);
          return alias;
        } catch (e) {
          if (isUniqueViolation(e)) throw new AliasTakenError(alias);
          throw e;
        }
      }
      // A generated code can collide with an existing custom alias; take the next one.
      for (let i = 0; i < MAX_ATTEMPTS; i++) {
        const code = await codes.next();
        try {
          await insert(code, longUrl);
          return code;
        } catch (e) {
          if (!isUniqueViolation(e)) throw e;
        }
      }
      throw new Error("could not allocate a unique code");
    },

    async resolve(code) {
      const { rows } = await pool.query("SELECT long_url FROM urls WHERE code = $1", [code]);
      return rows[0]?.long_url ?? null;
    },
  };
}
