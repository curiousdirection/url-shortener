import { Hono, type Context } from "hono";
import { zValidator } from "@hono/zod-validator";
import { z } from "zod";
import { AliasTakenError, type UrlService } from "./urlService.js";

const RESERVED = new Set(["api", "health"]);
// What a code can look like: the alias rules, or the generated 7
// characters.
// Anything else is a 404 without a database read (DynamoDB
// rejects keys over 2048 bytes).
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

// The address the client called.
// Behind CloudFront, X-Forwarded-Host holds it
// (forwarded-host.js).
const requestOrigin = (c: Context) => {
  const url = new URL(c.req.url);
  const forwarded = c.req.header("x-forwarded-host");
  return forwarded ? `${url.protocol}//${forwarded}` : url.origin;
};

// CloudFront caches a redirect for a year, browsers don't (so a
// takedown needs only an invalidation), and a 404 for 10
// seconds, so a new link works soon.
const CACHE_REDIRECT = "public, max-age=0, s-maxage=31536000";
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
