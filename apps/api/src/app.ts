import cors from "cors";
import express, { type Express, type NextFunction, type Request, type Response } from "express";
import { type ModuleDefinition, mountRouteRegistry } from "@sonora/kernel";

export type AppOptions = {
  readonly modules?: readonly ModuleDefinition[];
  // The one origin allowed to call the API from a browser. Without it, no origin is allowed.
  readonly webOrigin?: string;
};

// Headers a client could forge to pose as an internal caller or a signed-in principal. They are removed at the edge.
const FORGED_HEADER_PREFIXES = ["x-internal-", "x-principal-"] as const;
const FORGED_HEADERS = ["x-user-id", "x-profile-id"] as const;

export function createApp(options: AppOptions = {}): Express {
  const app = express();
  app.disable("x-powered-by");
  app.use(stripForgedHeaders);
  app.use(cors({ origin: options.webOrigin !== undefined ? [options.webOrigin] : false }));

  app.get("/health", (_request, response) => {
    response.json({ status: "ok" });
  });

  mountRouteRegistry(app, options.modules ?? []);

  return app;
}

function stripForgedHeaders(request: Request, _response: Response, next: NextFunction): void {
  for (const name of Object.keys(request.headers)) {
    if (isForged(name)) {
      delete request.headers[name];
    }
  }
  next();
}

function isForged(name: string): boolean {
  return (FORGED_HEADERS as readonly string[]).includes(name) || FORGED_HEADER_PREFIXES.some((prefix) => name.startsWith(prefix));
}
