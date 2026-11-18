import { z } from "zod";
import { defineRouteGroup } from "./route-group.js";

// Shapes match what packages/kernel answers from GET /health/live and GET /health/ready.
export const KernelStatusOk = z.object({ status: z.literal("ok") }).strict();
export const KernelStatusUnavailable = z.object({ status: z.literal("unavailable") }).strict();

export const kernelRouteGroup = defineRouteGroup({
  name: "kernel",
  routes: [
    { method: "get", path: "/health/live", responses: { 200: KernelStatusOk } },
    { method: "get", path: "/health/ready", responses: { 200: KernelStatusOk, 503: KernelStatusUnavailable } },
  ],
});
