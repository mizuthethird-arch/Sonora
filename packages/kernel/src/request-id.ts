import { randomUUID } from "node:crypto";
import type { RequestHandler } from "express";

const REQUEST_ID_HEADER = "x-request-id";

// A caller's ID is kept only when it is short and plain. Anything else is replaced, so it cannot inject into logs.
const VALID_CALLER_ID = /^[A-Za-z0-9._-]{1,64}$/;

export const requestId: RequestHandler = (request, response, next) => {
  const callerId = request.get(REQUEST_ID_HEADER);
  const id = callerId !== undefined && VALID_CALLER_ID.test(callerId) ? callerId : randomUUID();
  response.setHeader(REQUEST_ID_HEADER, id);
  next();
};
