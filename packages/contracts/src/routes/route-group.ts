import { type ZodType } from "zod";

export type HttpMethod = "get" | "post" | "put" | "patch" | "delete";

export type RouteContract = {
  readonly method: HttpMethod;
  readonly path: string;
  // Keyed by HTTP status code. Each body is a zod schema, so responses are validated on both sides.
  readonly responses: Readonly<Record<number, ZodType>>;
};

export type RouteGroup = {
  // The module that owns these routes, or "kernel" for routes the kernel serves.
  readonly name: string;
  readonly routes: readonly RouteContract[];
};

export function defineRouteGroup(group: RouteGroup): RouteGroup {
  return Object.freeze({ name: group.name, routes: [...group.routes] });
}
