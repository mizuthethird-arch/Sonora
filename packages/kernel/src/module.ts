import type { Router, RequestHandler } from "express";
import { type FacadeMethod } from "./request-context.js";
import { isPlainId } from "./request-id.js";

export type { FacadeMethod } from "./request-context.js";

export type ConsumerDefinition = {
  readonly queue: string;
  readonly handle: (message: unknown) => Promise<void>;
};

export type JobDefinition = {
  readonly name: string;
  readonly run: () => Promise<void>;
};

export type HttpMethod = "get" | "post" | "put" | "patch" | "delete";

// A route a module serves. The path is relative to the module's route prefix. The permission is "public" or a
// permission name such as catalog:track:read, enforced once sessions reach the registry.
export type RouteSpec = {
  readonly method: HttpMethod;
  readonly path: string;
  readonly permission: string;
  readonly handler: RequestHandler;
};

export type ModuleDefinition = {
  readonly name: string;
  readonly routePrefix: string;
  readonly routes: (router: Router) => void;
  readonly httpRoutes?: readonly RouteSpec[];
  readonly consumers: readonly ConsumerDefinition[];
  readonly jobs: readonly JobDefinition[];
  readonly facade: Readonly<Record<string, FacadeMethod<never, unknown>>>;
};

export type ModuleRegistry = {
  readonly modules: readonly ModuleDefinition[];
};

const ROUTE_PREFIX = /^\/[a-z0-9-]+$/;

export function defineModule(definition: ModuleDefinition): ModuleDefinition {
  if (!isPlainId(definition.name)) {
    throw new Error(`module name "${definition.name}" must be a plain identifier`);
  }
  if (!ROUTE_PREFIX.test(definition.routePrefix)) {
    throw new Error(`route prefix "${definition.routePrefix}" must be a slash followed by lowercase words`);
  }
  return Object.freeze({ ...definition });
}

// Boot fails when two modules claim the same name or route prefix, so routing never picks one silently.
export function loadModules(modules: readonly ModuleDefinition[]): ModuleRegistry {
  const owners = new Map<string, string>();
  for (const item of modules) {
    claim(owners, `route prefix "${item.routePrefix}"`, item.routePrefix, item.name);
    claim(owners, `module name "${item.name}"`, item.name, item.name);
  }
  return Object.freeze({ modules: [...modules] });
}

function claim(owners: Map<string, string>, label: string, key: string, owner: string): void {
  const previous = owners.get(key);
  if (previous !== undefined && previous !== owner) {
    throw new Error(`${label} is registered by both ${previous} and ${owner}`);
  }
  owners.set(key, owner);
}
