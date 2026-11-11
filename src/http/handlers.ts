import { z } from "zod";
import { AliasTakenError, type UrlService } from "../urlService.js";
import type { Route } from "./types.js";

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

export function createRoutes(service: UrlService, baseUrl: string): Route[] {
  return [
    {
      method: "GET",
      path: "/health",
      handler: async () => ({ status: 200, body: { status: "ok" } }),
    },
    {
      method: "POST",
      path: "/api/urls",
      handler: async ({ body }) => {
        const parsed = createSchema.safeParse(body);
        if (!parsed.success) {
          const issues = parsed.error.issues.map((i) => ({ path: i.path.join("."), message: i.message }));
          return { status: 400, body: { error: "invalid request", issues } };
        }
        const { url, alias } = parsed.data;
        try {
          const code = await service.create(url, alias);
          return { status: 201, body: { code, shortUrl: `${baseUrl}/${code}`, longUrl: url } };
        } catch (e) {
          if (e instanceof AliasTakenError) return { status: 409, body: { error: "alias already taken" } };
          throw e;
        }
      },
    },
    {
      method: "GET",
      path: "/:code",
      handler: async ({ params }) => {
        const longUrl = await service.resolve(params.code);
        if (!longUrl) return { status: 404, body: { error: "not found" } };
        return { status: 302, headers: { location: longUrl } };
      },
    },
  ];
}
