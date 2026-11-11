// Framework-agnostic HTTP types. Handlers only depend on these, never on Hono.
export interface HttpRequest {
  params: Record<string, string>;
  body?: unknown;
}

export interface HttpResponse {
  status: number;
  body?: unknown;
  headers?: Record<string, string>;
}

export type Handler = (req: HttpRequest) => Promise<HttpResponse>;

export interface Route {
  method: "GET" | "POST";
  path: string; // `:name` marks a path parameter
  handler: Handler;
}
