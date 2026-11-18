import { describe, expect, it } from "vitest";
import { defineModule, loadModules, type FacadeMethod } from "./module.js";

const listAlbums: FacadeMethod<{ limit: number }, string[]> = () => Promise.resolve(["album-1"]);

function catalogModule() {
  return defineModule({
    name: "catalog",
    routePrefix: "/catalog",
    routes: () => undefined,
    consumers: [{ queue: "catalog.track-imported", handle: () => Promise.resolve() }],
    jobs: [{ name: "reindex", run: () => Promise.resolve() }],
    facade: { listAlbums },
  });
}

describe("defineModule", () => {
  it("registers routes, consumers, jobs and a facade", () => {
    const catalog = catalogModule();

    expect(catalog.name).toBe("catalog");
    expect(catalog.routePrefix).toBe("/catalog");
    expect(catalog.consumers.map((consumer) => consumer.queue)).toEqual(["catalog.track-imported"]);
    expect(catalog.jobs.map((job) => job.name)).toEqual(["reindex"]);
    expect(Object.keys(catalog.facade)).toEqual(["listAlbums"]);
  });

  it("refuses a route prefix that does not start with a slash", () => {
    expect(() =>
      defineModule({ name: "catalog", routePrefix: "catalog", routes: () => undefined, consumers: [], jobs: [], facade: {} }),
    ).toThrow();
  });
});

describe("loadModules", () => {
  it("loads modules whose route prefixes differ", () => {
    const registry = loadModules([catalogModule(), defineModule({ name: "library", routePrefix: "/library", routes: () => undefined, consumers: [], jobs: [], facade: {} })]);

    expect(registry.modules.map((item) => item.name)).toEqual(["catalog", "library"]);
  });

  it("fails boot when two modules register the same route prefix", () => {
    const duplicate = defineModule({ name: "catalog-copy", routePrefix: "/catalog", routes: () => undefined, consumers: [], jobs: [], facade: {} });

    expect(() => loadModules([catalogModule(), duplicate])).toThrow(/\/catalog/);
  });
});
