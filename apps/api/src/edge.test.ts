import type { Request, Response } from "express";
import request from "supertest";
import { describe, expect, it } from "vitest";
import { defineModule } from "@sonora/kernel";
import { createApp } from "./app.js";

const WEB_ORIGIN = "https://sonora.example.test";

// A test-only module. Its route echoes the headers the handler received.
function echoModule() {
  return defineModule({
    name: "fixture-echo",
    routePrefix: "/fixture",
    routes: () => undefined,
    consumers: [],
    jobs: [],
    facade: {},
    httpRoutes: [
      {
        method: "get",
        path: "/echo",
        permission: "public",
        handler: (incoming: Request, response: Response) => {
          response.json({ headers: incoming.headers });
        },
      },
    ],
  });
}

async function headersSeenByHandler(extra: Record<string, string>): Promise<Record<string, unknown>> {
  const app = createApp({ modules: [echoModule()], webOrigin: WEB_ORIGIN });
  const response = await request(app).get("/fixture/echo").set(extra);
  return response.body.headers as Record<string, unknown>;
}

describe("edge header stripping", () => {
  it("removes client-supplied X-Internal-* headers before any route sees them", async () => {
    const seen = await headersSeenByHandler({ "x-internal-role": "admin", "x-internal-user": "someone" });

    expect(seen["x-internal-role"]).toBeUndefined();
    expect(seen["x-internal-user"]).toBeUndefined();
  });

  it("removes principal headers the client could forge", async () => {
    const seen = await headersSeenByHandler({
      "x-principal-user": "someone",
      "x-user-id": "someone",
      "x-profile-id": "someone",
    });

    expect(seen["x-principal-user"]).toBeUndefined();
    expect(seen["x-user-id"]).toBeUndefined();
    expect(seen["x-profile-id"]).toBeUndefined();
  });

  it("keeps ordinary headers", async () => {
    const seen = await headersSeenByHandler({ "x-request-id": "abc-123" });

    expect(seen["x-request-id"]).toBe("abc-123");
  });
});

describe("CORS", () => {
  it("allows the web origin only", async () => {
    const app = createApp({ modules: [echoModule()], webOrigin: WEB_ORIGIN });

    const response = await request(app).get("/fixture/echo").set("Origin", WEB_ORIGIN);

    expect(response.headers["access-control-allow-origin"]).toBe(WEB_ORIGIN);
  });

  it("gives no allow-origin header to another origin", async () => {
    const app = createApp({ modules: [echoModule()], webOrigin: WEB_ORIGIN });

    const response = await request(app).get("/fixture/echo").set("Origin", "https://evil.example.test");

    expect(response.headers["access-control-allow-origin"]).toBeUndefined();
  });

  it("refuses a preflight from another origin", async () => {
    const app = createApp({ modules: [echoModule()], webOrigin: WEB_ORIGIN });

    const response = await request(app)
      .options("/fixture/echo")
      .set("Origin", "https://evil.example.test")
      .set("Access-Control-Request-Method", "GET");

    expect(response.headers["access-control-allow-origin"]).toBeUndefined();
  });
});

describe("registry wiring in apps/api", () => {
  it("fails boot when two modules register the same route", () => {
    expect(() => createApp({ modules: [echoModule(), echoModule()], webOrigin: WEB_ORIGIN })).toThrow(/fixture\/echo/);
  });

  it("serves the routes of the modules it was given and keeps /health", async () => {
    const app = createApp({ modules: [echoModule()], webOrigin: WEB_ORIGIN });

    expect((await request(app).get("/fixture/echo")).status).toBe(200);
    expect((await request(app).get("/health")).status).toBe(200);
  });
});
