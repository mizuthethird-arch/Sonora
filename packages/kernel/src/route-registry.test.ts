import request from "supertest";
import { describe, expect, it } from "vitest";
import express from "express";
import { defineModule } from "./module.js";
import { buildRouteTable, mountRouteRegistry } from "./route-registry.js";

// A test-only module. It stands in for a real module so the registry can be tested without one.
function fixtureModule(name: string, prefix: string, routes: Parameters<typeof defineModule>[0]["httpRoutes"]) {
  return defineModule({
    name,
    routePrefix: prefix,
    routes: () => undefined,
    consumers: [],
    jobs: [],
    facade: {},
    httpRoutes: routes,
  });
}

const ok = (_request: express.Request, response: express.Response) => {
  response.json({ ok: true });
};

describe("mountRouteRegistry", () => {
  it("mounts each route under the prefix of the module that registered it", async () => {
    const app = express();
    const catalog = fixtureModule("fixture-catalog", "/fixture", [
      { method: "get", path: "/genres", permission: "public", handler: ok },
    ]);

    mountRouteRegistry(app, [catalog]);

    const response = await request(app).get("/fixture/genres");
    expect(response.status).toBe(200);
  });

  it("lists the permission of every route in the route table", () => {
    const catalog = fixtureModule("fixture-catalog", "/fixture", [
      { method: "get", path: "/genres", permission: "public", handler: ok },
      { method: "post", path: "/tracks", permission: "catalog:track:write", handler: ok },
    ]);

    expect(buildRouteTable([catalog])).toEqual([
      { module: "fixture-catalog", method: "get", fullPath: "/fixture/genres", permission: "public" },
      { module: "fixture-catalog", method: "post", fullPath: "/fixture/tracks", permission: "catalog:track:write" },
    ]);
  });

  it("refuses two modules that register the same method and path", () => {
    const first = fixtureModule("fixture-a", "/fixture", [
      { method: "get", path: "/genres", permission: "public", handler: ok },
    ]);
    const second = fixtureModule("fixture-b", "/fixture", [
      { method: "get", path: "/genres", permission: "public", handler: ok },
    ]);

    expect(() => buildRouteTable([first, second])).toThrow(/GET \/fixture\/genres.*fixture-a.*fixture-b/);
  });

  it("refuses a route without a permission", () => {
    const bad = fixtureModule("fixture-bad", "/fixture", [
      { method: "get", path: "/genres", permission: "", handler: ok },
    ]);

    expect(() => buildRouteTable([bad])).toThrow(/permission/);
  });

  it("refuses a route path that does not start with a slash", () => {
    const bad = fixtureModule("fixture-bad", "/fixture", [
      { method: "get", path: "genres", permission: "public", handler: ok },
    ]);

    expect(() => buildRouteTable([bad])).toThrow(/path/);
  });
});
