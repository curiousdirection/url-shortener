import { Hono } from "hono";
import type { HttpResponse, Route } from "./types.js";

function toResponse({ status, body, headers }: HttpResponse): Response {
  if (body === undefined) return new Response(null, { status, headers });
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });
}

// Registers framework-agnostic routes on a Hono app. Routes match in array order.
export function toHono(routes: Route[]): Hono {
  const app = new Hono();
  for (const route of routes) {
    app.on(route.method, route.path, async (c) => {
      // A missing or malformed JSON body becomes `undefined`; the handler's validation rejects it.
      const body = route.method === "GET" ? undefined : await c.req.json().catch(() => undefined);
      return toResponse(await route.handler({ params: c.req.param(), body }));
    });
  }
  return app;
}
