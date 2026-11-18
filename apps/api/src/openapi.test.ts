import request from "supertest";
import { describe, expect, it } from "vitest";
import { createApp } from "./app.js";

const WEB_ORIGIN = "https://sonora.example.test";

describe("GET /api/v1/openapi.json", () => {
  it("serves the merged OpenAPI 3.1 document outside production", async () => {
    const app = createApp({ webOrigin: WEB_ORIGIN, nodeEnv: "development" });

    const response = await request(app).get("/api/v1/openapi.json");

    expect(response.status).toBe(200);
    expect(response.type).toBe("application/json");
    expect(response.body.openapi).toBe("3.1.0");
    expect(response.body.paths).toHaveProperty("/health/live");
  });

  it("does not serve the document in production", async () => {
    const app = createApp({ webOrigin: WEB_ORIGIN, nodeEnv: "production" });

    const response = await request(app).get("/api/v1/openapi.json");

    expect(response.status).toBe(404);
  });
});
