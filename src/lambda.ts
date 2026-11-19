import { handle } from "hono/aws-lambda";
import { buildApp } from "./app.js";
import { config } from "./config.js";
import { createDb } from "./db.js";
import { createUrlService } from "./urlService.js";

// Created once per Lambda instance, not per request, so later requests reuse the DynamoDB client and its open connection.
export const handler = handle(buildApp(createUrlService(createDb(), config.tableName)));
