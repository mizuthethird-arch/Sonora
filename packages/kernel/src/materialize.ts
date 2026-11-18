import { chmod, mkdir, writeFile } from "node:fs/promises";
import { basename, join } from "node:path";
import { type EnvironmentName, type SecretStore } from "./secrets.js";

export type MaterializeInput = {
  readonly store: SecretStore;
  // The environment this run belongs to. Secrets of any other environment are refused before anything is written.
  readonly environment: EnvironmentName;
  readonly names: readonly string[];
  readonly directory: string;
};

const READ_ONLY_FOR_OWNER = 0o400;
const DIRECTORY_FOR_OWNER_ONLY = 0o700;

// Reads each secret and writes it to its own file, named by the last part of the secret name, mode 0400.
// The directory is created owner-only. Any missing secret stops the run before the container starts.
export async function materializeSecrets(input: MaterializeInput): Promise<string[]> {
  assertSameEnvironment(input);
  await mkdir(input.directory, { recursive: true, mode: DIRECTORY_FOR_OWNER_ONLY });
  const written: string[] = [];
  for (const name of input.names) {
    const value = await input.store.get(name);
    const path = join(input.directory, basename(name));
    await writeFile(path, value, { mode: READ_ONLY_FOR_OWNER });
    await chmod(path, READ_ONLY_FOR_OWNER);
    written.push(path);
  }
  return written;
}

function assertSameEnvironment(input: MaterializeInput): void {
  const prefix = `sonora/${input.environment}/`;
  for (const name of input.names) {
    if (!name.startsWith(prefix)) {
      throw new Error(`secret ${name} belongs to another environment; this run is ${input.environment}`);
    }
  }
}
