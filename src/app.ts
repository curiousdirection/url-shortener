import { createRoutes } from "./http/handlers.js";
import { toHono } from "./http/honoAdapter.js";
import type { UrlService } from "./urlService.js";

export function buildApp(service: UrlService, baseUrl: string) {
  return toHono(createRoutes(service, baseUrl));
}
