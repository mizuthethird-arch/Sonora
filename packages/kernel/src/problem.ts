import { STATUS_CODES } from "node:http";
import type { NextFunction, Request, Response } from "express";

export const PROBLEM_CONTENT_TYPE = "application/problem+json";

const INTERNAL_SERVER_ERROR = 500;
const MIN_CLIENT_ERROR = 400;
const MAX_CLIENT_ERROR = 499;

export function sendProblem(response: Response, status: number): void {
  response
    .status(status)
    .type(PROBLEM_CONTENT_TYPE)
    .json({ type: "about:blank", title: STATUS_CODES[status] ?? "Error", status });
}

export function notFoundHandler(_request: Request, response: Response): void {
  sendProblem(response, 404);
}

// Errors raised by Express and its body parser carry a 4xx status. Anything else becomes a generic 500,
// so no stack trace or internal message reaches the caller.
export function problemErrorHandler(error: unknown, _request: Request, response: Response, _next: NextFunction): void {
  sendProblem(response, statusOf(error));
}

function statusOf(error: unknown): number {
  if (typeof error !== "object" || error === null || !("status" in error)) {
    return INTERNAL_SERVER_ERROR;
  }
  const status = error.status;
  if (typeof status === "number" && status >= MIN_CLIENT_ERROR && status <= MAX_CLIENT_ERROR) {
    return status;
  }
  return INTERNAL_SERVER_ERROR;
}
