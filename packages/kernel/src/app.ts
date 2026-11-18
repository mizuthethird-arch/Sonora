import express, { type Express } from "express";

export type ReadinessCheck = () => Promise<void>;

export type AppOptions = {
  role: "api";
  readinessChecks: Record<string, ReadinessCheck>;
};

export function createApp(options: AppOptions): Express {
  const app = express();
  app.disable("x-powered-by");

  app.get("/health/live", (_request, response) => {
    response.json({ status: "ok" });
  });

  app.get("/health/ready", async (_request, response) => {
    const results = await Promise.allSettled(Object.values(options.readinessChecks).map((check) => check()));
    const ready = results.every((result) => result.status === "fulfilled");
    response.status(ready ? 200 : 503).json({ status: ready ? "ok" : "unavailable" });
  });

  return app;
}
