import { kernelRouteGroup } from "./kernel.js";
import { type RouteGroup } from "./route-group.js";

// Every route group in the repository. Add a group here when a module starts serving routes.
export const allRouteGroups: readonly RouteGroup[] = [kernelRouteGroup];

export { kernelRouteGroup } from "./kernel.js";
export { defineRouteGroup, type HttpMethod, type RouteContract, type RouteGroup } from "./route-group.js";
