import { describe, expect, it } from "vitest";
import { SHUTDOWN_TIMEOUT_MS, runGracefulShutdown, type Drain } from "./shutdown.js";

const SHORT_TIMEOUT_MS = 50;

describe("runGracefulShutdown", () => {
  it("reports drained when every drain finishes in time", async () => {
    const order: string[] = [];
    const drains: Drain[] = [
      { name: "http", drain: () => Promise.resolve(void order.push("http")) },
      { name: "consumers", drain: () => Promise.resolve(void order.push("consumers")) },
      { name: "jobs", drain: () => Promise.resolve(void order.push("jobs")) },
    ];

    const outcome = await runGracefulShutdown(drains, SHORT_TIMEOUT_MS);

    expect(outcome).toBe("drained");
    expect(order.sort()).toEqual(["consumers", "http", "jobs"]);
  });

  it("reports timed-out when a drain does not finish before the deadline", async () => {
    const drains: Drain[] = [{ name: "jobs", drain: () => new Promise<void>(() => undefined) }];

    const started = Date.now();
    const outcome = await runGracefulShutdown(drains, SHORT_TIMEOUT_MS);

    expect(outcome).toBe("timed-out");
    expect(Date.now() - started).toBeLessThan(1000);
  });

  it("still runs the other drains when one fails", async () => {
    const ran: string[] = [];
    const drains: Drain[] = [
      { name: "http", drain: () => Promise.reject(new Error("socket reset")) },
      { name: "consumers", drain: () => Promise.resolve(void ran.push("consumers")) },
    ];

    const outcome = await runGracefulShutdown(drains, SHORT_TIMEOUT_MS);

    expect(ran).toEqual(["consumers"]);
    expect(outcome).toBe("failed");
  });
});

describe("SHUTDOWN_TIMEOUT_MS", () => {
  it("allows 20 seconds to drain", () => {
    expect(SHUTDOWN_TIMEOUT_MS).toBe(20000);
  });
});
