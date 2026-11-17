import { z } from "zod";

const DEFAULT_PORT = 3000;
const LOWEST_PORT = 1;
const HIGHEST_PORT = 65535;

const portSchema = z
  .string()
  .regex(/^\d{1,5}$/)
  .transform(Number)
  .pipe(z.number().min(LOWEST_PORT).max(HIGHEST_PORT));

const environmentSchema = z.object({
  PORT: portSchema.default(DEFAULT_PORT),
});

export type Config = {
  port: number;
};

export function loadConfig(environment: Record<string, string | undefined>): Config {
  const result = environmentSchema.safeParse(environment);

  if (!result.success) {
    throw new Error(`Invalid configuration: PORT must be a whole number from ${LOWEST_PORT} to ${HIGHEST_PORT}`);
  }

  return { port: result.data.PORT };
}
