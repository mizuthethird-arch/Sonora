import pino, { type DestinationStream, type Logger } from "pino";

export type LoggerOptions = {
  destination?: DestinationStream;
};

// Paths whose values never reach a log line. Extend this list, never remove from it.
const REDACTED_PATHS = [
  "password",
  "*.password",
  "token",
  "*.token",
  "req.headers.authorization",
  "req.headers.cookie",
  "headers.authorization",
  "headers.cookie",
];

const CENSOR = "[Redacted]";

export function createLogger(options: LoggerOptions = {}): Logger {
  return pino({ redact: { paths: REDACTED_PATHS, censor: CENSOR } }, options.destination);
}
