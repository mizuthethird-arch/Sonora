import { z } from "zod";

const DEFAULT_PORT = 3000;
const LOWEST_PORT = 1;
const HIGHEST_PORT = 65535;
const INVALID_PORT_MESSAGE = `Invalid configuration: PORT must be a whole number from ${LOWEST_PORT} to ${HIGHEST_PORT}`;

// The text is checked before it becomes a number, because Number() would accept "1e3" and "3.5".
// Digits only, no leading zero, at most five digits.
const PORT_TEXT = /^[1-9]\d{0,4}$/;

const portSchema = z
  .string()
  .regex(PORT_TEXT)
  .transform(Number)
  .pipe(z.number().min(LOWEST_PORT).max(HIGHEST_PORT));

const environmentSchema = z.object({
  PORT: portSchema.default(DEFAULT_PORT),
  WEB_ORIGIN: z.url().optional(),
  TRUST_PROXY_HOPS: z.string().regex(/^[0-5]$/).transform(Number).optional(),
});

export type Config = {
  port: number;
  webOrigin?: string;
  trustProxyHops?: number;
};

export function loadConfig(environment: Record<string, string | undefined>): Config {
  const result = environmentSchema.safeParse(environment);

  if (!result.success) {
    throw new Error(INVALID_PORT_MESSAGE);
  }

  return { port: result.data.PORT, webOrigin: result.data.WEB_ORIGIN, trustProxyHops: result.data.TRUST_PROXY_HOPS };
}
