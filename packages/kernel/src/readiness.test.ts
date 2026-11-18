import { describe, expect, it } from "vitest";
import { READINESS_TIMEOUT_MS, runReadinessChecks } from "./readiness.js";

const SHORT_TIMEOUT_MS = 50;

describe("runReadinessChecks", () => {
  it("is ready when every check passes", async () => {
    const ready = await runReadinessChecks({ mysql: () => Promise.resolve(), redis: () => Promise.resolve() }, SHORT_TIMEOUT_MS);

    expect(ready).toBe(true);
  });

  it("is not ready when one check rejects", async () => {
    const ready = await runReadinessChecks(
      { mysql: () => Promise.resolve(), redis: () => Promise.reject(new Error("refused")) },
      SHORT_TIMEOUT_MS,
    );

    expect(ready).toBe(false);
  });

  it("is not ready when a check does not answer in time", async () => {
    const hangs = () => new Promise<void>(() => undefined);

    const started = Date.now();
    const ready = await runReadinessChecks({ mysql: hangs }, SHORT_TIMEOUT_MS);

    expect(ready).toBe(false);
    expect(Date.now() - started).toBeLessThan(1000);
  });

  it("is ready with no checks registered", async () => {
    expect(await runReadinessChecks({}, SHORT_TIMEOUT_MS)).toBe(true);
  });
});

describe("READINESS_TIMEOUT_MS", () => {
  it("is 2 seconds per check", () => {
    expect(READINESS_TIMEOUT_MS).toBe(2000);
  });
});
