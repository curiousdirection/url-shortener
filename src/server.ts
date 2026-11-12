import { serve } from "@hono/node-server";
import { buildApp } from "./app.js";
import { createCodeGenerator } from "./codeGenerator.js";
import { config } from "./config.js";
import { createPool } from "./db.js";
import { createUrlService } from "./urlService.js";

const pool = createPool();
const app = buildApp(createUrlService(pool, createCodeGenerator(pool)), config.baseUrl);

const server = serve({ fetch: app.fetch, port: config.port }, (info) =>
  console.log(`listening on :${info.port}`),
);

// On SIGTERM (instance refresh, scale-in): stop accepting connections, let
// in-flight requests finish, close the pool, then exit.
let shuttingDown = false;
const shutdown = (signal: string) => {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`${signal} received, shutting down`);

  // Backstop in case a client holds a connection open. Keep it below the 30 s that systemd
  // (TimeoutStopSec) gives the service to stop. When deployed behind a load balancer and an
  // auto scaling group, SIGTERM arrives after traffic has drained.
  setTimeout(() => process.exit(1), 25_000).unref();

  // close() also drops idle keep-alive connections (Node 19+).
  server.close(async (err) => {
    if (err) console.error(err);
    await pool.end().catch(console.error);
    process.exit(err ? 1 : 0);
  });
};
process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
