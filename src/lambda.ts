import { handle } from "hono/aws-lambda";
import { buildApp } from "./app.js";
import { config } from "./config.js";
import { createDb } from "./db.js";
import { createUrlService } from "./urlService.js";

// Built outside the handler, so a warm Lambda reuses the client.
export const handler = handle(buildApp(createUrlService(createDb(), config.tableName)));
