import { readFile } from "node:fs/promises";
import { join, normalize, sep } from "node:path";

// The eleven modules, one MySQL user each (T013 and T025). A new module is added here and in its migrations.
export const MODULE_NAMES = [
  "identity",
  "catalog",
  "media",
  "playback",
  "library",
  "search",
  "recommender",
  "realtime",
  "notification",
  "analytics",
  "platform",
] as const;

export const ENVIRONMENT_NAMES = ["staging", "production"] as const;

export type ModuleName = (typeof MODULE_NAMES)[number];
export type EnvironmentName = (typeof ENVIRONMENT_NAMES)[number];

export type SecretStore = {
  get: (name: string) => Promise<string>;
};

export class SecretNotFoundError extends Error {
  constructor(name: string) {
    super(`secret not found: ${name}`);
    this.name = "SecretNotFoundError";
  }
}

const SECRET_NAME = /^sonora\/(staging|production)\/[a-z0-9-]+(\/[a-z0-9-]+)*$/;

// The AWS-style name of one module's database password in one environment.
export function moduleSecretName(environment: string, module: string): string {
  if (!isEnvironment(environment)) {
    throw new Error(`unknown environment: ${environment}`);
  }
  if (!isModule(module)) {
    throw new Error(`unknown module: ${module}`);
  }
  return `sonora/${environment}/db/${module}`;
}

// Stands in for AWS Secrets Manager and SSM locally: a secret named sonora/<env>/db/<module> is the file
// <directory>/sonora/<env>/db/<module>. The real AWS store is a TODO (docs/secrets.md).
export function createLocalSecretStore(directory: string): SecretStore {
  return {
    get: async (name) => {
      if (!SECRET_NAME.test(name) || name.includes("..")) {
        throw new Error(`refused secret name: ${name}`);
      }
      const path = normalize(join(directory, ...name.split("/")));
      if (!path.startsWith(normalize(directory) + sep)) {
        throw new Error(`refused secret name: ${name}`);
      }
      try {
        return (await readFile(path, "utf8")).replace(/\r?\n$/, "");
      } catch (error) {
        if (isMissingFile(error)) {
          throw new SecretNotFoundError(name);
        }
        throw error;
      }
    },
  };
}

function isEnvironment(value: string): value is EnvironmentName {
  return (ENVIRONMENT_NAMES as readonly string[]).includes(value);
}

function isModule(value: string): value is ModuleName {
  return (MODULE_NAMES as readonly string[]).includes(value);
}

function isMissingFile(error: unknown): boolean {
  return typeof error === "object" && error !== null && "code" in error && error.code === "ENOENT";
}
