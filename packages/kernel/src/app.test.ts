import request from "supertest";
import { describe, expect, it } from "vitest";
import { createApp } from "./app.js";

const healthyChecks = {
  mysql: () => Promise.resolve(),
  redis: () => Promise.resolve(),
  rabbitmq: () => Promise.resolve(),
};

describe("createApp with ROLE=api", () => {
  it("serves GET /health/live with 200", async () => {
    const app = createApp({ role: "api", readinessChecks: healthyChecks });

    const response = await request(app).get("/health/live");

    expect(response.status).toBe(200);
  });

  it("serves GET /health/ready with 200 when MySQL, Redis and RabbitMQ are reachable", async () => {
    const app = createApp({ role: "api", readinessChecks: healthyChecks });

    const response = await request(app).get("/health/ready");

    expect(response.status).toBe(200);
  });
});
