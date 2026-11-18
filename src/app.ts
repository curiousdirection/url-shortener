import { Hono, type Context } from "hono";
import { zValidator } from "@hono/zod-validator";
import { z } from "zod";
import { AliasTakenError, type UrlService } from "./urlService.js";

const RESERVED = new Set(["api", "health"]);
// What a code can look like: the alias rules, or the generated 7 characters. Anything else is a
// 404 without a database read (DynamoDB rejects keys over 2048 bytes).
const CODE_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

const createSchema = z.object({
  url: z
    .string()
    .max(2048)
    .refine((v) => {
      try {
        const p = new URL(v).protocol;
        return p === "http:" || p === "https:";
      } catch {
        return false;
      }
    }, "must be a valid http(s) URL"),
  alias: z
    .string()
    .regex(/^[A-Za-z0-9_-]{3,64}$/, "3-64 chars: letters, digits, _ or -")
    .refine((v) => !RESERVED.has(v.toLowerCase()), "alias is reserved")
    .optional(),
});

// What a Host header can look like. Anything else is ignored.
const HOST_PATTERN = /^[A-Za-z0-9.-]+(:\d{1,5})?$/;

// The address the client called. Behind CloudFront the request's own host is the function URL's,
// so a CloudFront Function on /api/* copies the viewer's Host into X-Forwarded-Host
// (infra/app/functions/forwarded-host.js). Only CloudFront can call the function, so that header
// can be trusted. Without it (local dev, tests) the request's own host is used.
// Behind a proxy the request can arrive as plain http, and X-Forwarded-Proto says whether the
// client used https. A Lambda function URL sets it.
const requestOrigin = (c: Context) => {
  const { protocol, host } = new URL(c.req.url);
  const forwarded = c.req.header("x-forwarded-host");
  const publicHost = forwarded && HOST_PATTERN.test(forwarded) ? forwarded : host;
  return c.req.header("x-forwarded-proto") === "https" ? `https://${publicHost}` : `${protocol}//${publicHost}`;
};

// The CDN follows these (infra/app/cdn.tf). A redirect is cached by the CDN for a day (s-maxage)
// but not by browsers (max-age=0), so a link taken down is gone once the CDN's copy is cleared.
// A 404 is cached for only 10 seconds, so a link created just after a miss works soon. /health
// must never be cached.
const CACHE_REDIRECT = "public, max-age=0, s-maxage=86400";
const CACHE_NOT_FOUND = "public, max-age=10";
const CACHE_NONE = "no-store";

export function buildApp(service: UrlService) {
  const app = new Hono();

  app.get("/health", (c) => {
    c.header("Cache-Control", CACHE_NONE);
    return c.json({ status: "ok" });
  });

  app.post("/api/urls", zValidator("json", createSchema), async (c) => {
    const { url, alias } = c.req.valid("json");
    try {
      const code = await service.create(url, alias);
      return c.json({ code, shortUrl: `${requestOrigin(c)}/${code}`, longUrl: url }, 201);
    } catch (e) {
      if (e instanceof AliasTakenError) return c.json({ error: "alias already taken" }, 409);
      throw e;
    }
  });

  app.get("/:code", async (c) => {
    const code = c.req.param("code");
    const longUrl = CODE_PATTERN.test(code) ? await service.resolve(code) : null;
    if (!longUrl) {
      c.header("Cache-Control", CACHE_NOT_FOUND);
      return c.json({ error: "not found" }, 404);
    }
    c.header("Cache-Control", CACHE_REDIRECT);
    return c.redirect(longUrl, 302);
  });

  return app;
}
