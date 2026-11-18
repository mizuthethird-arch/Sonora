import { chmod, mkdir, rename, writeFile } from "node:fs/promises";
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
    // Write a new file, then rename it over the old one. A read-only file cannot be opened for writing,
    // but the directory can still replace it, so a rotated secret is written on the next run.
    const temporary = `${path}.${process.pid}.tmp`;
    await writeFile(temporary, value, { mode: READ_ONLY_FOR_OWNER });
    await chmod(temporary, READ_ONLY_FOR_OWNER);
    await rename(temporary, path);
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
