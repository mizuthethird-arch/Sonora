import request from "supertest";
import { describe, expect, it } from "vitest";
import { createApp } from "./app.js";

describe("GET /health", () => {
  it("responds 200 with a JSON status of ok", async () => {
    const response = await request(createApp()).get("/health");

    expect(response.status).toBe(200);
    expect(response.type).toBe("application/json");
    expect(response.body).toEqual({ status: "ok" });
  });

  it("answers HEAD without a body", async () => {
    const response = await request(createApp()).head("/health");

    expect(response.status).toBe(200);
    expect(response.text ?? "").toBe("");
  });

  it("does not accept writes", async () => {
    const response = await request(createApp()).post("/health").send({ status: "down" });

    expect(response.status).toBe(404);
  });

  it("ignores query strings and hostile characters", async () => {
    const response = await request(createApp()).get("/health?x=%3Cscript%3E%00");

    expect(response.status).toBe(200);
    expect(response.body).toEqual({ status: "ok" });
  });

  it("does not expose server details", async () => {
    const response = await request(createApp()).get("/health");

    expect(response.headers["x-powered-by"]).toBeUndefined();
  });
});

describe("unknown routes", () => {
  it("respond 404", async () => {
    const response = await request(createApp()).get("/does-not-exist");

    expect(response.status).toBe(404);
  });
});
