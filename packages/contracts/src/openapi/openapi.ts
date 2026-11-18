import { OpenAPIRegistry, OpenApiGeneratorV31 } from "@asteasolutions/zod-to-openapi";
import { type RouteGroup } from "../routes/route-group.js";

export type OpenApiDocument = ReturnType<OpenApiGeneratorV31["generateDocument"]>;

const DOCUMENT_TITLE = "Sonora API";
const DOCUMENT_VERSION = "1.0.0";

// One document per route group, for review and for the group's own consumers.
export function buildGroupDocument(group: RouteGroup): OpenApiDocument {
  return buildDocument([group]);
}

// The one document apps/api serves: every route group merged.
export function buildMergedDocument(groups: readonly RouteGroup[]): OpenApiDocument {
  return buildDocument(groups);
}

function buildDocument(groups: readonly RouteGroup[]): OpenApiDocument {
  const registry = new OpenAPIRegistry();
  for (const group of groups) {
    for (const route of group.routes) {
      registry.registerPath({
        method: route.method,
        path: route.path,
        tags: [group.name],
        responses: Object.fromEntries(
          Object.entries(route.responses).map(([status, schema]) => [
            status,
            { description: `HTTP ${status}`, content: { "application/json": { schema } } },
          ]),
        ),
      });
    }
  }
  const generator = new OpenApiGeneratorV31(registry.definitions);
  return generator.generateDocument({
    openapi: "3.1.0",
    info: { title: DOCUMENT_TITLE, version: DOCUMENT_VERSION },
  });
}
