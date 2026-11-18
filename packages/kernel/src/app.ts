import express, { type Express } from "express";
import helmet from "helmet";
import { problemErrorHandler, notFoundHandler } from "./problem.js";
import { requestId } from "./request-id.js";

export type ReadinessCheck = () => Promise<void>;

export type AppOptions = {
  role: "api";
  readinessChecks: Record<string, ReadinessCheck>;
  mountRoutes?: (app: Express) => void;
};

const JSON_BODY_LIMIT = "1mb";

export function createApp(options: AppOptions): Express {
  const app = express();
  app.disable("x-powered-by");
  app.use(helmet());
  app.use(requestId);
  app.use(express.json({ limit: JSON_BODY_LIMIT }));

  app.get("/health/live", (_request, response) => {
    response.json({ status: "ok" });
  });

  app.get("/health/ready", async (_request, response) => {
    const results = await Promise.allSettled(Object.values(options.readinessChecks).map((check) => check()));
    const ready = results.every((result) => result.status === "fulfilled");
    response.status(ready ? 200 : 503).json({ status: ready ? "ok" : "unavailable" });
  });

  options.mountRoutes?.(app);

  app.use(notFoundHandler);
  app.use(problemErrorHandler);

  return app;
}
