import { describe, expect, it } from "vitest";
import { kernelRouteGroup } from "./kernel.js";
import { allRouteGroups } from "./index.js";
import { type RouteGroup } from "./route-group.js";

describe("kernel route group", () => {
  const routes = kernelRouteGroup.routes;

  it("is named after the kernel, not a product module", () => {
    expect(kernelRouteGroup.name).toBe("kernel");
  });

  it("describes GET /health/live with a 200 body of status ok", () => {
    const live = routes.find((route) => route.path === "/health/live");

    expect(live?.method).toBe("get");
    expect(live?.responses[200]?.safeParse({ status: "ok" }).success).toBe(true);
    expect(live?.responses[200]?.safeParse({ status: "down" }).success).toBe(false);
  });

  it("describes GET /health/ready with 200 ok and 503 unavailable", () => {
    const ready = routes.find((route) => route.path === "/health/ready");

    expect(ready?.responses[200]?.safeParse({ status: "ok" }).success).toBe(true);
    expect(ready?.responses[503]?.safeParse({ status: "unavailable" }).success).toBe(true);
    expect(ready?.responses[503]?.safeParse({ status: "ok" }).success).toBe(false);
  });

  it("refuses extra fields in a response", () => {
    const live = routes.find((route) => route.path === "/health/live");

    expect(live?.responses[200]?.safeParse({ status: "ok", extra: 1 }).success).toBe(false);
  });
});

describe("route groups", () => {
  it("have unique names", () => {
    const names = allRouteGroups.map((group: RouteGroup) => group.name);

    expect(new Set(names).size).toBe(names.length);
  });

  it("do not register the same method and path twice", () => {
    const keys = allRouteGroups.flatMap((group) => group.routes.map((route) => `${route.method} ${route.path}`));

    expect(new Set(keys).size).toBe(keys.length);
  });

  it("use absolute paths", () => {
    for (const group of allRouteGroups) {
      for (const route of group.routes) {
        expect(route.path.startsWith("/")).toBe(true);
      }
    }
  });
});
