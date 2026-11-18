import request from "supertest";
import { describe, expect, it } from "vitest";
import { createApp } from "./app.js";

const healthyChecks = { mysql: () => Promise.resolve() };
const ONE_MEGABYTE = 1024 * 1024;

function makeApp() {
  return createApp({ role: "api", readinessChecks: healthyChecks });
}

describe("security headers", () => {
  it("sets helmet headers such as nosniff", async () => {
    const response = await request(makeApp()).get("/health/live");

    expect(response.headers["x-content-type-options"]).toBe("nosniff");
  });
});

describe("request IDs", () => {
  it("generates an x-request-id when the caller sends none", async () => {
    const response = await request(makeApp()).get("/health/live");

    expect(response.headers["x-request-id"]).toMatch(/^[0-9a-f-]{36}$/);
  });

  it("keeps a valid caller x-request-id", async () => {
    const response = await request(makeApp()).get("/health/live").set("x-request-id", "abc-123");

    expect(response.headers["x-request-id"]).toBe("abc-123");
  });

  it("replaces a hostile caller x-request-id", async () => {
    const response = await request(makeApp()).get("/health/live").set("x-request-id", "<script>");

    expect(response.headers["x-request-id"]).toMatch(/^[0-9a-f-]{36}$/);
  });
});

describe("body limit", () => {
  it("rejects a JSON body over 1 MB with 413 problem+json", async () => {
    const oversized = JSON.stringify({ padding: "a".repeat(ONE_MEGABYTE + 1) });

    const response = await request(makeApp())
      .post("/health/live")
      .set("content-type", "application/json")
      .send(oversized);

    expect(response.status).toBe(413);
    expect(response.type).toBe("application/problem+json");
    expect(response.body.status).toBe(413);
  });
});

describe("problem+json errors", () => {
  it("answers an unknown route with 404 problem+json", async () => {
    const response = await request(makeApp()).get("/does-not-exist");

    expect(response.status).toBe(404);
    expect(response.type).toBe("application/problem+json");
    expect(response.body).toMatchObject({ status: 404 });
  });

  it("answers an unexpected error with a generic 500 and no stack", async () => {
    const app = createApp({
      role: "api",
      readinessChecks: healthyChecks,
      mountRoutes: (routes) => {
        routes.get("/boom", () => {
          throw new Error("secret internal detail");
        });
      },
    });

    const response = await request(app).get("/boom");

    expect(response.status).toBe(500);
    expect(response.type).toBe("application/problem+json");
    expect(JSON.stringify(response.body)).not.toContain("secret internal detail");
    expect(JSON.stringify(response.body)).not.toContain("stack");
  });
});
