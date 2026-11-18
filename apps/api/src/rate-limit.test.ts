import type { Request, Response } from "express";
import request from "supertest";
import { describe, expect, it } from "vitest";
import { defineModule } from "@sonora/kernel";
import { createApp } from "./app.js";

const WEB_ORIGIN = "https://sonora.example.test";
const LIMITS = {
  general: { max: 5, windowMs: 60_000 },
  auth: { max: 2, windowMs: 60_000 },
};

// Test-only module: one ordinary route and one auth route. Auth routes sit under the /auth prefix.
function fixtureModules() {
  const ok = (_request: Request, response: Response) => {
    response.json({ ok: true });
  };
  return [
    defineModule({
      name: "fixture-general",
      routePrefix: "/fixture",
      routes: () => undefined,
      consumers: [],
      jobs: [],
      facade: {},
      httpRoutes: [{ method: "get", path: "/echo", permission: "public", handler: ok }],
    }),
    defineModule({
      name: "fixture-auth",
      routePrefix: "/auth",
      routes: () => undefined,
      consumers: [],
      jobs: [],
      facade: {},
      httpRoutes: [{ method: "post", path: "/login", permission: "public", handler: ok }],
    }),
  ];
}

describe("rate limits per IP", () => {
  it("answers 429 with a Retry-After once an ordinary route is over its limit", async () => {
    const app = createApp({ modules: fixtureModules(), webOrigin: WEB_ORIGIN, rateLimits: LIMITS });

    for (let attempt = 0; attempt < LIMITS.general.max; attempt += 1) {
      expect((await request(app).get("/fixture/echo")).status).toBe(200);
    }
    const limited = await request(app).get("/fixture/echo");

    expect(limited.status).toBe(429);
    expect(Number(limited.headers["retry-after"])).toBeGreaterThan(0);
  });

  it("applies the stricter auth limit to /auth routes even while ordinary routes still have room", async () => {
    const app = createApp({ modules: fixtureModules(), webOrigin: WEB_ORIGIN, rateLimits: LIMITS });

    for (let attempt = 0; attempt < LIMITS.auth.max; attempt += 1) {
      expect((await request(app).post("/auth/login")).status).toBe(200);
    }
    const limited = await request(app).post("/auth/login");

    expect(limited.status).toBe(429);
    expect(Number(limited.headers["retry-after"])).toBeGreaterThan(0);
    expect((await request(app).get("/fixture/echo")).status).toBe(200);
  });
});
