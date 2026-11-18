import { type Express } from "express";
import { type HttpMethod, type ModuleDefinition, type RouteSpec } from "./module.js";

export type RouteEntry = {
  readonly module: string;
  readonly method: HttpMethod;
  readonly fullPath: string;
  readonly permission: string;
};

const PERMISSION = /^(public|[a-z][a-z-]*(:[a-z][a-z-]*)+)$/;

// Builds the route table and refuses anything ambiguous: two modules on the same method and path, a route
// without a valid permission, or a path that does not start with a slash. Nothing is mounted when this throws.
export function buildRouteTable(modules: readonly ModuleDefinition[]): RouteEntry[] {
  const owners = new Map<string, string>();
  const entries: RouteEntry[] = [];
  for (const module of modules) {
    for (const route of module.httpRoutes ?? []) {
      assertValidRoute(module.name, route);
      const fullPath = fullPathOf(module, route);
      const key = `${route.method.toUpperCase()} ${fullPath}`;
      const owner = owners.get(key);
      if (owner !== undefined) {
        throw new Error(`route ${key} is registered by both ${owner} and ${module.name}`);
      }
      owners.set(key, module.name);
      entries.push({ module: module.name, method: route.method, fullPath, permission: route.permission });
    }
  }
  return entries;
}

// Mounts every module's routes under its prefix. A module can only reach the paths it registered.
export function mountRouteRegistry(app: Express, modules: readonly ModuleDefinition[]): void {
  buildRouteTable(modules);
  for (const module of modules) {
    for (const route of module.httpRoutes ?? []) {
      mountOne(app, route, fullPathOf(module, route));
    }
  }
}

function fullPathOf(module: ModuleDefinition, route: RouteSpec): string {
  return route.path === "/" ? module.routePrefix : `${module.routePrefix}${route.path}`;
}

function assertValidRoute(moduleName: string, route: RouteSpec): void {
  if (!PERMISSION.test(route.permission)) {
    throw new Error(`route ${route.method.toUpperCase()} ${route.path} in ${moduleName} needs a permission: "public" or a name such as catalog:track:read`);
  }
  if (!route.path.startsWith("/")) {
    throw new Error(`route path "${route.path}" in ${moduleName} must start with a slash`);
  }
}

function mountOne(app: Express, route: RouteSpec, fullPath: string): void {
  switch (route.method) {
    case "get":
      app.get(fullPath, route.handler);
      return;
    case "post":
      app.post(fullPath, route.handler);
      return;
    case "put":
      app.put(fullPath, route.handler);
      return;
    case "patch":
      app.patch(fullPath, route.handler);
      return;
    case "delete":
      app.delete(fullPath, route.handler);
      return;
  }
}
