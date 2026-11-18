import { randomUUID } from "node:crypto";
import type { RequestHandler } from "express";

const REQUEST_ID_HEADER = "x-request-id";

// An identifier is kept only when it is short and plain, so it cannot inject into logs.
const PLAIN_ID = /^[A-Za-z0-9._-]{1,64}$/;

export function isPlainId(value: string): boolean {
  return PLAIN_ID.test(value);
}

export const requestId: RequestHandler = (request, response, next) => {
  const callerId = request.get(REQUEST_ID_HEADER);
  const id = callerId !== undefined && isPlainId(callerId) ? callerId : randomUUID();
  response.setHeader(REQUEST_ID_HEADER, id);
  next();
};
