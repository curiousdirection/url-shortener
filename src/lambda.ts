import type { Hono } from "hono";
import { handle } from "hono/aws-lambda";
import { HTTPException } from "hono/http-exception";
import { buildApp } from "./app.js";
import { config } from "./config.js";
import { createDb } from "./db.js";
import { createUrlService } from "./urlService.js";

export const toLambdaHandler = (app: Hono) => {
  // Rethrown so Lambda counts a crash as an error for the errors alarm; Hono's own handler answers 500, which Lambda counts as a success.
  app.onError((err) => {
    if (err instanceof HTTPException) return err.getResponse();
    throw err;
  });
  return handle(app);
};

// Created once per Lambda instance, not per request, so later requests reuse the DynamoDB client and its open connection.
export const handler = toLambdaHandler(buildApp(createUrlService(createDb(), config.tableName), { blockedDomains: config.blockedDomains }));
