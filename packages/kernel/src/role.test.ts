import request from "supertest";
import { describe, expect, it } from "vitest";
import { createApp } from "./app.js";
import { parseRole, roleProfile, ROLES } from "./role.js";

const healthyChecks = { mysql: () => Promise.resolve() };

describe("parseRole", () => {
  it.each(ROLES)("accepts %s", (role) => {
    expect(parseRole(role)).toBe(role);
  });

  it("fails with a message that names the value and lists the allowed roles", () => {
    expect(() => parseRole("bogus")).toThrow(/bogus/);
    expect(() => parseRole("bogus")).toThrow(/api, worker, media-worker, realtime/);
  });

  it("fails when ROLE is missing", () => {
    expect(() => parseRole(undefined)).toThrow(/ROLE/);
  });

  it("is case sensitive", () => {
    expect(() => parseRole("API")).toThrow();
  });
});

describe("roleProfile", () => {
  it("api serves HTTP and not WebSockets", () => {
    expect(roleProfile("api")).toMatchObject({ http: true, websockets: false });
  });

  it("worker runs the outbox and consumers and serves no HTTP", () => {
    expect(roleProfile("worker")).toMatchObject({ http: false, outbox: true, consumers: true });
  });

  it("media-worker runs only media jobs", () => {
    expect(roleProfile("media-worker")).toEqual(
      expect.objectContaining({ http: false, outbox: false, consumers: false, mediaJobs: true }),
    );
  });

  it("realtime runs only the WebSocket server", () => {
    expect(roleProfile("realtime")).toEqual(
      expect.objectContaining({ http: false, websockets: true, outbox: false, mediaJobs: false }),
    );
  });
});

describe("createApp per role", () => {
  it("refuses API routes for media-worker", () => {
    expect(() =>
      createApp({
        role: "media-worker",
        readinessChecks: healthyChecks,
        mountRoutes: (routes) => routes.get("/library", (_request, response) => response.json([])),
      }),
    ).toThrow(/media-worker/);
  });

  it("answers the health endpoints for media-worker", async () => {
    const app = createApp({ role: "media-worker", readinessChecks: healthyChecks });

    expect((await request(app).get("/health/live")).status).toBe(200);
    expect((await request(app).get("/health/ready")).status).toBe(200);
  });
});
