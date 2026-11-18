import { z } from "zod";
import { defineRouteGroup } from "./route-group.js";

// Shapes match what packages/kernel answers from GET /health/live and GET /health/ready.
const okStatus = z.object({ status: z.literal("ok") }).strict();
const unavailableStatus = z.object({ status: z.literal("unavailable") }).strict();

export const kernelRouteGroup = defineRouteGroup({
  name: "kernel",
  routes: [
    { method: "get", path: "/health/live", responses: { 200: okStatus } },
    { method: "get", path: "/health/ready", responses: { 200: okStatus, 503: unavailableStatus } },
  ],
});
