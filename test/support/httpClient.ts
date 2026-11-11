import { createServer, type RequestListener, type Server } from "node:http";
import type { AddressInfo } from "node:net";

// Test client that serves any Node request listener (e.g. an Express app) on an ephemeral port.
export function createClient(app: RequestListener) {
  const server: Server = createServer(app);
  const ready = new Promise<string>((resolve) =>
    server.listen(0, "127.0.0.1", () => resolve(`http://127.0.0.1:${(server.address() as AddressInfo).port}`)),
  );

  return {
    // Redirects are not followed, so tests can assert on the 302 itself.
    get: async (path: string) => fetch(`${await ready}${path}`, { redirect: "manual" }),
    post: async (path: string, body: unknown) =>
      fetch(`${await ready}${path}`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(body),
      }),
    close: () => new Promise<void>((resolve) => server.close(() => resolve())),
  };
}
