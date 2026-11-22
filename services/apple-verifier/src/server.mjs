/**
 * Optional local Node host for the review-only verifier. No deployment
 * manifest and no process starts without explicit PIPO_APPLE_HTTP_SERVER_ENABLED.
 * Put a TLS-terminating authenticated reverse proxy in front of this only
 * after separate deployment approval; never expose service_role secrets.
 */
import http from "node:http";
import { Readable } from "node:stream";
import { createAppleVerificationHandler, configFromEnvironment } from "./handler.mjs";

export function createLocalServer(env = process.env) {
  if (env.PIPO_APPLE_HTTP_SERVER_ENABLED !== "true") {
    throw new Error("Apple verification HTTP server is disabled");
  }
  if (env.PIPO_APPLE_HOST && env.PIPO_APPLE_HOST !== "127.0.0.1") {
    throw new Error("Review-only host must bind to loopback");
  }
  const handler = createAppleVerificationHandler({
    config: configFromEnvironment(env),
  });
  return http.createServer(async (incoming, outgoing) => {
    try {
      const body = incoming.method === "POST" ? Readable.toWeb(incoming) : undefined;
      const request = new Request(
        "http://127.0.0.1" + (incoming.url ?? "/"),
        {
          method: incoming.method,
          headers: incoming.headers,
          ...(body ? { body, duplex: "half" } : {}),
        },
      );
      const response = await handler(request);
      outgoing.writeHead(response.status, Object.fromEntries(response.headers));
      if (response.body) {
        for await (const chunk of response.body) outgoing.write(chunk);
      }
      outgoing.end();
    } catch {
      // Never reflect a raw Apple signedPayload, secret or stack trace.
      outgoing.writeHead(503, {
        "content-type": "application/json", "cache-control": "no-store",
      });
      outgoing.end(JSON.stringify({ error: "verification_unavailable" }));
    }
  });
}

if (import.meta.url === new URL("file://" + process.argv[1]).href) {
  const server = createLocalServer();
  const port = Number(process.env.PIPO_APPLE_PORT || 8788);
  if (!Number.isSafeInteger(port) || port < 1024 || port > 65535) {
    throw new Error("Invalid local port");
  }
  server.listen(port, "127.0.0.1");
}
