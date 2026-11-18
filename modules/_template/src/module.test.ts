import { describe, expect, it } from "vitest";
import { templateModule } from "../module.js";

describe("templateModule", () => {
  it("registers under the template name and route prefix", () => {
    const module = templateModule({ repository: { save: () => Promise.resolve() }, newId: () => "ex-1" });

    expect(module.name).toBe("template");
    expect(module.routePrefix).toBe("/template");
  });

  it("exposes the createExample facade method", () => {
    const module = templateModule({ repository: { save: () => Promise.resolve() }, newId: () => "ex-1" });

    expect(Object.keys(module.facade)).toEqual(["createExample"]);
  });
});
