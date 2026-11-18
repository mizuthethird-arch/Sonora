import { describe, expect, it } from "vitest";
import { decideCompatibility, findBreakingChanges, type ContractSnapshot } from "./compatibility.js";

function response(properties: Record<string, unknown>, required: string[] = []): unknown {
  return {
    type: "object",
    properties,
    required,
  };
}

function snapshot(schema: unknown, version = "1.0.0"): ContractSnapshot {
  return {
    version,
    paths: { "/things": { get: { responses: { "200": { content: { "application/json": { schema } } } } } } },
  };
}

describe("findBreakingChanges", () => {
  it("reports a removed response field", () => {
    const base = snapshot(response({ id: { type: "string" }, title: { type: "string" } }));
    const current = snapshot(response({ id: { type: "string" } }));

    expect(findBreakingChanges(base, current)).toEqual([expect.stringContaining("title")]);
  });

  it("reports a narrowed enum", () => {
    const base = snapshot(response({ status: { enum: ["ok", "unavailable"] } }));
    const current = snapshot(response({ status: { enum: ["ok"] } }));

    expect(findBreakingChanges(base, current)).toEqual([expect.stringContaining("unavailable")]);
  });

  it("reports a removed constant value", () => {
    const base = snapshot(response({ status: { const: "ok" } }));
    const current = snapshot(response({ status: { const: "done" } }));

    expect(findBreakingChanges(base, current).length).toBeGreaterThan(0);
  });

  it("does not report an added field", () => {
    const base = snapshot(response({ id: { type: "string" } }));
    const current = snapshot(response({ id: { type: "string" }, title: { type: "string" } }));

    expect(findBreakingChanges(base, current)).toEqual([]);
  });

  it("does not report a widened enum", () => {
    const base = snapshot(response({ status: { enum: ["ok"] } }));
    const current = snapshot(response({ status: { enum: ["ok", "unavailable"] } }));

    expect(findBreakingChanges(base, current)).toEqual([]);
  });

  it("reports a removed path", () => {
    const base = snapshot(response({ id: { type: "string" } }));
    const current: ContractSnapshot = { version: "1.0.0", paths: {} };

    expect(findBreakingChanges(base, current)).toEqual([expect.stringContaining("/things")]);
  });
});

describe("decideCompatibility", () => {
  const breaking = ["removed field title"];
  const overlapUntil = "2027-03-01";

  it("allows a change with no breaking entries and an unchanged version", () => {
    expect(decideCompatibility({ breaking: [], baseVersion: "1.0.0", currentVersion: "1.0.0", overlapUntil: null })).toEqual({ allowed: true });
  });

  it("rejects a breaking change when the version is not bumped", () => {
    const decision = decideCompatibility({ breaking, baseVersion: "1.0.0", currentVersion: "1.0.0", overlapUntil });

    expect(decision.allowed).toBe(false);
  });

  it("rejects a breaking change with a bumped version but no overlap period", () => {
    const decision = decideCompatibility({ breaking, baseVersion: "1.0.0", currentVersion: "2.0.0", overlapUntil: null });

    expect(decision.allowed).toBe(false);
  });

  it("allows a breaking change with a bumped version and a noted overlap period", () => {
    const decision = decideCompatibility({ breaking, baseVersion: "1.0.0", currentVersion: "2.0.0", overlapUntil });

    expect(decision).toEqual({ allowed: true });
  });
});
