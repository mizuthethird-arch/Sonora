import { mkdtempSync, readFileSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { materializeSecrets } from "./materialize.js";
import { type SecretStore } from "./secrets.js";

let root: string;

beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), "sonora-materialize-"));
});

afterEach(() => {
  rmSync(root, { recursive: true, force: true });
});

function memoryStore(values: Record<string, string>): SecretStore {
  return {
    get: (name) => {
      const value = values[name];
      return value === undefined ? Promise.reject(new Error(`secret not found: ${name}`)) : Promise.resolve(value);
    },
  };
}

describe("materializeSecrets", () => {
  it("writes each secret to its own file with the value as the content", async () => {
    const store = memoryStore({
      "sonora/staging/db/identity": "identity-value",
      "sonora/staging/db/catalog": "catalog-value",
    });
    const target = join(root, "run");

    const written = await materializeSecrets({
      store,
      environment: "staging",
      names: ["sonora/staging/db/identity", "sonora/staging/db/catalog"],
      directory: target,
    });

    expect(written).toHaveLength(2);
    expect(readFileSync(join(target, "identity"), "utf8")).toBe("identity-value");
    expect(readFileSync(join(target, "catalog"), "utf8")).toBe("catalog-value");
  });

  it("makes every file read-only for its owner (mode 0400)", async () => {
    const store = memoryStore({ "sonora/staging/db/identity": "identity-value" });
    const target = join(root, "run");

    await materializeSecrets({ store, environment: "staging", names: ["sonora/staging/db/identity"], directory: target });

    expect(statSync(join(target, "identity")).mode & 0o777).toBe(0o400);
  });

  it("fails when a secret is missing and writes nothing for it", async () => {
    const store = memoryStore({});
    const target = join(root, "run");

    await expect(
      materializeSecrets({ store, environment: "staging", names: ["sonora/staging/db/identity"], directory: target }),
    ).rejects.toThrow(/sonora\/staging\/db\/identity/);
  });
});
