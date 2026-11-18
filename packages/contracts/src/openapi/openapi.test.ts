import { describe, expect, it } from "vitest";
import { kernelRouteGroup } from "../routes/kernel.js";
import { allRouteGroups } from "../routes/index.js";
import { buildGroupDocument, buildMergedDocument } from "./openapi.js";

describe("buildGroupDocument", () => {
  it("is OpenAPI 3.1 and lists the group's paths only", () => {
    const document = buildGroupDocument(kernelRouteGroup);

    expect(document.openapi).toBe("3.1.0");
    expect(Object.keys(document.paths ?? {}).sort()).toEqual(["/health/live", "/health/ready"]);
  });

  it("describes each response with its zod schema as JSON Schema", () => {
    const document = buildGroupDocument(kernelRouteGroup);
    const live = document.paths?.["/health/live"]?.get?.responses?.["200"];
    const body = JSON.stringify(live);

    expect(body).toContain("application/json");
    expect(body).toContain('"ok"');
  });
});

describe("buildMergedDocument", () => {
  it("contains the paths of every route group", () => {
    const document = buildMergedDocument(allRouteGroups);
    const expected = allRouteGroups.flatMap((group) => group.routes.map((route) => route.path));

    expect(Object.keys(document.paths ?? {}).sort()).toEqual([...new Set(expected)].sort());
    expect(document.openapi).toBe("3.1.0");
  });
});
