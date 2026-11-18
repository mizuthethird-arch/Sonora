import { randomUUID } from "node:crypto";
import type { Request, Response } from "express";
import { createClient } from "redis";
import request from "supertest";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { defineModule } from "@sonora/kernel";
import { createApp } from "../app.js";
import { createRedisRateLimitStore } from "./rate-limit-store.js";

const WEB_ORIGIN = "https://sonora.example.test";
const LIMITS = { general: { max: 2, windowMs: 60_000 }, auth: { max: 10, windowMs: 60_000 } };
const REDIS_URL = process.env["REDIS_URL"] ?? "redis://localhost:6379";

const client = createClient({ url: REDIS_URL });

beforeAll(async () => {
  await client.connect();
});

afterAll(async () => {
  await client.quit();
});

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

describe("Redis-backed rate limits", () => {
  it("shares one count between two API instances that use the same Redis", async () => {
    const store = createRedisRateLimitStore(client, `test-${randomUUID()}:`);
    const first = createApp({ modules: echoModules(), webOrigin: WEB_ORIGIN, rateLimits: LIMITS, rateLimitStore: store, trustProxyHops: 1 });
    const second = createApp({ modules: echoModules(), webOrigin: WEB_ORIGIN, rateLimits: LIMITS, rateLimitStore: store, trustProxyHops: 1 });

    expect((await request(first).get("/fixture/echo").set("X-Forwarded-For", "203.0.113.9")).status).toBe(200);
    expect((await request(second).get("/fixture/echo").set("X-Forwarded-For", "203.0.113.9")).status).toBe(200);

    const limited = await request(first).get("/fixture/echo").set("X-Forwarded-For", "203.0.113.9");
    expect(limited.status).toBe(429);
    expect(Number(limited.headers["retry-after"])).toBeGreaterThan(0);
  });
});
