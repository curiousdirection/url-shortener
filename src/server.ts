import { serve } from "@hono/node-server";
import { buildApp } from "./app.js";
import { config } from "./config.js";
import { createDb } from "./db.js";
import { createUrlService } from "./urlService.js";

// For local development only.
// In AWS the app runs as a Lambda function (src/lambda.ts).
const app = buildApp(createUrlService(createDb(), config.tableName));

serve({ fetch: app.fetch, port: config.port }, (info) => console.log(`listening on :${info.port}`));
