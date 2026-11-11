import { Redis } from "ioredis";
import { config } from "./config.js";

export const createRedis = () => new Redis(config.redisUrl);
