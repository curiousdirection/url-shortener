import type { Redis } from "ioredis";
import { encode } from "./base62.js";

const COUNTER_KEY = "url:counter";
// Offset so generated codes start at 6 characters.
const OFFSET = 62n ** 5n;

export interface CodeGenerator {
  next(): Promise<string>;
}

export function createCodeGenerator(redis: Redis): CodeGenerator {
  return {
    async next() {
      const n = await redis.incr(COUNTER_KEY);
      return encode(OFFSET + BigInt(n));
    },
  };
}
