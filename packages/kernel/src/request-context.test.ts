import { describe, expect, expectTypeOf, it } from "vitest";
import { createRequestContext, type FacadeMethod, type RequestContext } from "./request-context.js";

const CORRELATION_ID = "0b6f1c2e-7a3d-4f0e-9c1b-5d2e8a7f4c10";

describe("createRequestContext", () => {
  it("carries the user, profile, permissions and correlation ID it was given", () => {
    const context = createRequestContext({
      correlationId: CORRELATION_ID,
      user: { id: "user-1" },
      profile: { id: "profile-1" },
      permissions: ["library:read"],
    });

    expect(context.correlationId).toBe(CORRELATION_ID);
    expect(context.user).toEqual({ id: "user-1" });
    expect(context.profile).toEqual({ id: "profile-1" });
    expect(context.permissions.has("library:read")).toBe(true);
  });

  it("describes an anonymous caller with no user, no profile and no permissions", () => {
    const context = createRequestContext({ correlationId: CORRELATION_ID });

    expect(context.user).toBeNull();
    expect(context.profile).toBeNull();
    expect(context.permissions.size).toBe(0);
  });

  it("refuses an empty correlation ID", () => {
    expect(() => createRequestContext({ correlationId: "" })).toThrow();
  });

  it("refuses a correlation ID with hostile characters", () => {
    expect(() => createRequestContext({ correlationId: "<script>" })).toThrow();
  });

  it("is frozen so a module cannot change it mid-request", () => {
    const context = createRequestContext({ correlationId: CORRELATION_ID });

    expect(Object.isFrozen(context)).toBe(true);
  });
});

describe("FacadeMethod", () => {
  it("requires a RequestContext as its first parameter", () => {
    expectTypeOf<FacadeMethod<string, number>>().parameter(0).toEqualTypeOf<RequestContext>();
  });

  it("returns a promise of the output", () => {
    expectTypeOf<FacadeMethod<string, number>>().returns.toEqualTypeOf<Promise<number>>();
  });
});
