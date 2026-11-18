import type { Request, Response } from "express";
import request from "supertest";
import { describe, expect, it } from "vitest";
import { defineModule } from "@sonora/kernel";
import { createApp } from "./app.js";

const WEB_ORIGIN = "https://sonora.example.test";
const LIMITS = {
  general: { max: 2, windowMs: 60_000 },
  auth: { max: 10, windowMs: 60_000 },
};

function echoModules() {
  return [
    defineModule({
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
          handler: (_request: Request, response: Response) => {
            response.json({ ok: true });
          },
        },
      ],
    }),
  ];
}

describe("trust proxy", () => {
  it("counts each client behind the proxy separately when one hop is trusted", async () => {
    const app = createApp({ modules: echoModules(), webOrigin: WEB_ORIGIN, rateLimits: LIMITS, trustProxyHops: 1 });

    for (let attempt = 0; attempt < LIMITS.general.max; attempt += 1) {
      expect((await request(app).get("/fixture/echo").set("X-Forwarded-For", "203.0.113.5")).status).toBe(200);
    }
    expect((await request(app).get("/fixture/echo").set("X-Forwarded-For", "203.0.113.5")).status).toBe(429);
    expect((await request(app).get("/fixture/echo").set("X-Forwarded-For", "203.0.113.6")).status).toBe(200);
  });

  it("ignores X-Forwarded-For when no proxy is trusted, so every caller shares one limit", async () => {
    const app = createApp({ modules: echoModules(), webOrigin: WEB_ORIGIN, rateLimits: LIMITS });

    for (let attempt = 0; attempt < LIMITS.general.max; attempt += 1) {
      await request(app).get("/fixture/echo").set("X-Forwarded-For", "203.0.113.5");
    }

    expect((await request(app).get("/fixture/echo").set("X-Forwarded-For", "203.0.113.6")).status).toBe(429);
  });
});
