import { describe, expect, it } from "vitest";
import { z } from "zod";
import { eventSchema } from "./event-envelope.js";

// A test-only event. No product event is defined by this step.
const sample = eventSchema({
  type: "contracts.sample-happened",
  version: 1,
  payload: z.object({ count: z.number().int().nonnegative() }).strict(),
});

const validEvent = {
  id: "0190f3c4-7b2a-7d4e-8f1a-2c3d4e5f6a7b",
  type: "contracts.sample-happened",
  version: 1,
  occurred_at: "2026-11-18T07:30:00.000Z",
  correlation_id: "req-abc-123",
  payload: { count: 3 },
};

describe("event envelope", () => {
  it("accepts a complete event with a valid payload", () => {
    expect(sample.safeParse(validEvent).success).toBe(true);
  });

  it.each(["id", "type", "version", "occurred_at", "correlation_id", "payload"])(
    "rejects an event without %s",
    (field) => {
      const { [field]: _removed, ...withoutField } = validEvent;

      expect(sample.safeParse(withoutField).success).toBe(false);
    },
  );

  it("rejects a payload that does not match its schema", () => {
    expect(sample.safeParse({ ...validEvent, payload: { count: -1 } }).success).toBe(false);
  });

  it("rejects an event whose type is not the one declared", () => {
    expect(sample.safeParse({ ...validEvent, type: "contracts.other" }).success).toBe(false);
  });

  it("rejects an event whose version is not the one declared", () => {
    expect(sample.safeParse({ ...validEvent, version: 2 }).success).toBe(false);
  });

  it("rejects a non-UTC or malformed occurred_at", () => {
    expect(sample.safeParse({ ...validEvent, occurred_at: "yesterday" }).success).toBe(false);
  });

  it("rejects a correlation_id with hostile characters", () => {
    expect(sample.safeParse({ ...validEvent, correlation_id: "<script>" }).success).toBe(false);
  });

  it("rejects extra top-level fields", () => {
    expect(sample.safeParse({ ...validEvent, extra: true }).success).toBe(false);
  });
});
