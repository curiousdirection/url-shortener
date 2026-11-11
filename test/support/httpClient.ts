// Minimal HTTP client for tests. `send` decides where requests go: an in-memory
// Hono app (`app.request`) or a real server (`fetch(baseUrl + path, init)`).
export type Send = (path: string, init?: RequestInit) => Response | Promise<Response>;

export function createClient(send: Send) {
  return {
    // Redirects are not followed, so tests can assert on the 302 itself.
    get: async (path: string) => send(path, { redirect: "manual" }),
    post: async (path: string, body: unknown) =>
      send(path, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(body),
      }),
  };
}
