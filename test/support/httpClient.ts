// Minimal test client over anything with a `request` method (e.g. a Hono app).
type App = { request: (path: string, init?: RequestInit) => Response | Promise<Response> };

export function createClient(app: App) {
  return {
    // Redirects are not followed, so tests can assert on the 302 itself.
    get: async (path: string) => app.request(path, { redirect: "manual" }),
    post: async (path: string, body: unknown) =>
      app.request(path, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(body),
      }),
  };
}
