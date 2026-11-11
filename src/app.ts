import { Hono } from "hono";
import { zValidator } from "@hono/zod-validator";
import { z } from "zod";
import { AliasTakenError, type UrlService } from "./urlService.js";

const RESERVED = new Set(["api", "health"]);

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

export function buildApp(service: UrlService, baseUrl: string) {
  const app = new Hono();

  app.get("/health", (c) => c.json({ status: "ok" }));

  app.post("/api/urls", zValidator("json", createSchema), async (c) => {
    const { url, alias } = c.req.valid("json");
    try {
      const code = await service.create(url, alias);
      return c.json({ code, shortUrl: `${baseUrl}/${code}`, longUrl: url }, 201);
    } catch (e) {
      if (e instanceof AliasTakenError) return c.json({ error: "alias already taken" }, 409);
      throw e;
    }
  });

  app.get("/:code", async (c) => {
    const longUrl = await service.resolve(c.req.param("code"));
    if (!longUrl) return c.json({ error: "not found" }, 404);
    return c.redirect(longUrl, 302);
  });

  return app;
}
