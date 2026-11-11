import express, { type ErrorRequestHandler } from "express";
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
  const app = express();
  app.disable("x-powered-by");
  app.use(express.json());

  app.get("/health", (_req, res) => {
    res.json({ status: "ok" });
  });

  app.post("/api/urls", async (req, res) => {
    const parsed = createSchema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: "invalid request", issues: parsed.error.issues });
      return;
    }
    const { url, alias } = parsed.data;
    try {
      const code = await service.create(url, alias);
      res.status(201).json({ code, shortUrl: `${baseUrl}/${code}`, longUrl: url });
    } catch (e) {
      if (e instanceof AliasTakenError) {
        res.status(409).json({ error: "alias already taken" });
        return;
      }
      throw e;
    }
  });

  app.get("/:code", async (req, res) => {
    const longUrl = await service.resolve(req.params.code);
    if (!longUrl) {
      res.status(404).json({ error: "not found" });
      return;
    }
    res.redirect(302, longUrl);
  });

  // Express 5 forwards rejected async handlers here. Client errors (e.g. malformed JSON) keep their status.
  const onError: ErrorRequestHandler = (err, _req, res, _next) => {
    const status = typeof err?.status === "number" && err.status >= 400 && err.status < 500 ? err.status : 500;
    if (status === 500) console.error(err);
    res.status(status).json({ error: status === 500 ? "internal server error" : "bad request" });
  };
  app.use(onError);

  return app;
}
