import { z } from "zod";

export type ConfigDeps = {
  readonly exit: (code: number) => void;
  readonly log: (message: string) => void;
};

const EXIT_CODE_INVALID_CONFIGURATION = 1;

// Parses the environment with a zod schema. The error names the keys only, never their values,
// so a secret cannot end up in a log line.
export function loadConfig<Schema extends z.ZodObject>(
  schema: Schema,
  environment: Readonly<Record<string, string | undefined>>,
): z.output<Schema> {
  const result = schema.safeParse(environment);
  if (!result.success) {
    throw new ConfigError(badKeys(result.error));
  }
  return result.data;
}

// Boot entry point: logs the bad keys and exits with code 1 instead of starting with bad configuration.
export function bootConfig<Schema extends z.ZodObject>(
  schema: Schema,
  environment: Readonly<Record<string, string | undefined>>,
  deps: ConfigDeps,
): z.output<Schema> | undefined {
  try {
    return loadConfig(schema, environment);
  } catch (error) {
    deps.log(error instanceof Error ? error.message : "invalid configuration");
    deps.exit(EXIT_CODE_INVALID_CONFIGURATION);
    return undefined;
  }
}

export class ConfigError extends Error {
  readonly keys: readonly string[];

  constructor(keys: readonly string[]) {
    super(`invalid configuration: missing or invalid ${keys.join(", ")}`);
    this.name = "ConfigError";
    this.keys = keys;
  }
}

function badKeys(error: z.ZodError): string[] {
  const keys = error.issues.map((issue) => String(issue.path[0] ?? "environment"));
  return [...new Set(keys)].sort();
}
