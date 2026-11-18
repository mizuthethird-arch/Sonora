import { describe, expect, it } from "vitest";
import { createContractsClient } from "./client.js";

function fakeFetch(status: number, body: unknown, seen: string[] = []) {
  return (input: string | URL) => {
    seen.push(String(input));
    return Promise.resolve(
      new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } }),
    );
  };
}

describe("contracts client", () => {
  it("calls GET /health/live on the base URL and returns the parsed body", async () => {
    const seen: string[] = [];
    const client = createContractsClient({ baseUrl: "https://api.example.test", fetch: fakeFetch(200, { status: "ok" }, seen) });

    const live = await client.liveness();

    expect(seen).toEqual(["https://api.example.test/health/live"]);
    expect(live).toEqual({ status: "ok" });
  });

  it("returns the 503 readiness body typed as unavailable", async () => {
    const client = createContractsClient({
      baseUrl: "https://api.example.test",
      fetch: fakeFetch(503, { status: "unavailable" }),
    });

    expect(await client.readiness()).toEqual({ status: "unavailable" });
  });

  it("throws when a response body does not match its schema", async () => {
    const client = createContractsClient({ baseUrl: "https://api.example.test", fetch: fakeFetch(200, { status: "down" }) });

    await expect(client.liveness()).rejects.toThrow(/does not match/);
  });

  it("throws on a status the route does not declare", async () => {
    const client = createContractsClient({ baseUrl: "https://api.example.test", fetch: fakeFetch(500, { status: "ok" }) });

    await expect(client.liveness()).rejects.toThrow(/status 500/);
  });
});
