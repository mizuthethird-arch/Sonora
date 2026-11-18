import cors from "cors";
import express, { type Express, type NextFunction, type Request, type Response } from "express";
import { rateLimit } from "express-rate-limit";
import { type ModuleDefinition, mountRouteRegistry } from "@sonora/kernel";
import { allRouteGroups, buildMergedDocument, CONTRACT_VERSION } from "@sonora/contracts";

export type AppOptions = {
  readonly modules?: readonly ModuleDefinition[];
  // The one origin allowed to call the API from a browser. Without it, no origin is allowed.
  readonly webOrigin?: string;
  readonly rateLimits?: RateLimits;
  // The NODE_ENV of the process. The OpenAPI document is not served when it is "production".
  readonly nodeEnv?: string;
  // How many reverse proxies sit in front of the API (Traefik is one). Zero trusts no forwarded address.
  readonly trustProxyHops?: number;
};

export type RateLimit = { readonly max: number; readonly windowMs: number };
export type RateLimits = { readonly general: RateLimit; readonly auth: RateLimit };

// Proposed numbers for review: 300 requests a minute per IP for everything, and 10 a minute for /auth.
export const DEFAULT_RATE_LIMITS: RateLimits = {
  general: { max: 300, windowMs: 60_000 },
  auth: { max: 10, windowMs: 60_000 },
};

// Headers a client could forge to pose as an internal caller or a signed-in principal. They are removed at the edge.
const FORGED_HEADER_PREFIXES = ["x-internal-", "x-principal-"] as const;
const FORGED_HEADERS = ["x-user-id", "x-profile-id"] as const;

export function createApp(options: AppOptions = {}): Express {
  const app = express();
  app.disable("x-powered-by");
  if (options.trustProxyHops !== undefined && options.trustProxyHops > 0) {
    app.set("trust proxy", options.trustProxyHops);
  }
  app.use(stripForgedHeaders);
  app.use(cors({ origin: options.webOrigin !== undefined ? [options.webOrigin] : false }));
  const limits = options.rateLimits ?? DEFAULT_RATE_LIMITS;
  app.use("/auth", limiter(limits.auth));
  app.use(limiter(limits.general));

  app.get("/health", (_request, response) => {
    response.json({ status: "ok" });
  });

  mountRouteRegistry(app, options.modules ?? []);

  if (options.nodeEnv !== "production") {
    const document = buildMergedDocument(allRouteGroups, CONTRACT_VERSION);
    app.get("/api/v1/openapi.json", (_request, response) => {
      response.json(document);
    });
  }

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

// Per IP. Retry-After is the length of the window, an upper bound on when the caller may try again.
function limiter(limit: RateLimit) {
  return rateLimit({
    windowMs: limit.windowMs,
    limit: limit.max,
    standardHeaders: "draft-7",
    legacyHeaders: false,
    handler: (_request, response) => {
      response.set("Retry-After", String(Math.ceil(limit.windowMs / 1000)));
      response.status(429).json({ type: "about:blank", title: "Too Many Requests", status: 429 });
    },
  });
}
