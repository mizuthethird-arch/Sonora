import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { fetchDownload } from "./download.ts";

type Route = { status: number; body: string };

const routes: Record<string, Route> = {
  "/ok": { status: 200, body: "audio-bytes" },
  "/missing": { status: 404, body: "not found" },
  "/busy": { status: 429, body: "slow down" },
};

function respond(request: IncomingMessage, response: ServerResponse): void {
  if (request.url === "/hang") {
    // Never answers, so the request stays open until the client gives up or the server closes.
    return;
  }
  const route = routes[request.url ?? ""];
  if (route === undefined) {
    response.writeHead(500);
    response.end();
    return;
  }
  response.writeHead(route.status, { "content-type": "text/plain" });
  response.end(route.body);
}

let server: Server;
let baseUrl = "";

beforeAll(async () => {
  server = createServer(respond);
  await new Promise<void>((resolve) => {
    server.listen(0, "127.0.0.1", () => resolve());
  });
  const address = server.address() as AddressInfo;
  baseUrl = `http://127.0.0.1:${address.port}`;
});

afterAll(async () => {
  // Drops any request still open on /hang so that close can finish.
  server.closeAllConnections();
  await new Promise<void>((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
});

describe("fetchDownload", () => {
  it("returns status 200 and the bytes served for an ok url", async () => {
    const result = await fetchDownload(`${baseUrl}/ok`);

    expect(result.status).toBe(200);
    expect(new TextDecoder().decode(result.body)).toBe("audio-bytes");
  });

  it("returns status 404 without throwing for a missing url", async () => {
    const result = await fetchDownload(`${baseUrl}/missing`);

    expect(result.status).toBe(404);
  });

  it("returns status 429 without throwing for a busy url", async () => {
    const result = await fetchDownload(`${baseUrl}/busy`);

    expect(result.status).toBe(429);
  });

  it("rejects when the server does not answer within the timeout", async () => {
    await expect(fetchDownload(`${baseUrl}/hang`, 100)).rejects.toThrow();
  });
});
