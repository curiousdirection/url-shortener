import { serve } from "@hono/node-server";
import { buildApp } from "./app.js";
import { createCodeGenerator } from "./codeGenerator.js";
import { config } from "./config.js";
import { createPool } from "./db.js";
import { createUrlService } from "./urlService.js";

const pool = createPool();
const app = buildApp(createUrlService(pool, createCodeGenerator(pool)), config.baseUrl);

serve({ fetch: app.fetch, port: config.port }, (info) =>
  console.log(`listening on :${info.port}`),
);
