import { describe, expect, it } from "vitest";
import { z } from "zod";
import { type RouteGroup } from "../routes/route-group.js";
import { buildMergedDocument } from "../openapi/openapi.js";
import { checkContracts } from "./check-contracts.js";

function group(responseSchema: z.ZodType): RouteGroup {
  return {
    name: "sample",
    routes: [{ method: "get", path: "/sample", responses: { 200: responseSchema } }],
  };
}

const wide = group(z.object({ id: z.string(), title: z.string() }).strict());
const narrow = group(z.object({ id: z.string() }).strict());

describe("checkContracts", () => {
  it("passes when the contract is unchanged", () => {
    const document = buildMergedDocument([wide], "1.0.0");

    const result = checkContracts({
      base: { document, contract: { version: "1.0.0", overlapUntil: null } },
      current: { document, contract: { version: "1.0.0", overlapUntil: null } },
    });

    expect(result).toEqual({ allowed: true, breaking: [] });
  });

  it("fails when a field is removed and the version is not bumped", () => {
    const result = checkContracts({
      base: { document: buildMergedDocument([wide], "1.0.0"), contract: { version: "1.0.0", overlapUntil: null } },
      current: { document: buildMergedDocument([narrow], "1.0.0"), contract: { version: "1.0.0", overlapUntil: null } },
    });

    expect(result.allowed).toBe(false);
    expect(result.breaking.join("\n")).toMatch(/title/);
  });

  it("passes a removed field when the version is bumped and an overlap period is noted", () => {
    const result = checkContracts({
      base: { document: buildMergedDocument([wide], "1.0.0"), contract: { version: "1.0.0", overlapUntil: null } },
      current: { document: buildMergedDocument([narrow], "1.0.0"), contract: { version: "2.0.0", overlapUntil: "2027-03-01" } },
    });

    expect(result.allowed).toBe(true);
    expect(result.breaking.length).toBeGreaterThan(0);
  });
});
