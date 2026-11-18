import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { MODULE_NAMES, createLocalSecretStore, moduleSecretName, SecretNotFoundError } from "./secrets.js";

let directory: string;

beforeEach(() => {
  directory = mkdtempSync(join(tmpdir(), "sonora-secrets-"));
});

afterEach(() => {
  rmSync(directory, { recursive: true, force: true });
});

describe("moduleSecretName", () => {
  it("names each module's database password per environment", () => {
    expect(moduleSecretName("staging", "identity")).toBe("sonora/staging/db/identity");
    expect(moduleSecretName("production", "catalog")).toBe("sonora/production/db/catalog");
  });

  it("covers the eleven modules", () => {
    expect(MODULE_NAMES).toHaveLength(11);
  });

  it("refuses an unknown module or environment", () => {
    expect(() => moduleSecretName("staging", "payments")).toThrow();
    expect(() => moduleSecretName("qa", "identity")).toThrow();
  });
});

describe("createLocalSecretStore", () => {
  it("reads the value stored under an AWS-style name", async () => {
    mkdirSync(join(directory, "sonora/staging/db"), { recursive: true });
    writeFileSync(join(directory, "sonora/staging/db/identity"), "value-one\n");

    const store = createLocalSecretStore(directory);

    expect(await store.get("sonora/staging/db/identity")).toBe("value-one");
  });

  it("fails with a not-found error that names the secret but not any value", async () => {
    const store = createLocalSecretStore(directory);

    await expect(store.get("sonora/staging/db/identity")).rejects.toBeInstanceOf(SecretNotFoundError);
    await expect(store.get("sonora/staging/db/identity")).rejects.toThrow(/sonora\/staging\/db\/identity/);
  });

  it("refuses a name that tries to leave the store directory", async () => {
    const store = createLocalSecretStore(directory);

    await expect(store.get("sonora/../../etc/passwd")).rejects.toThrow();
  });

  it("refuses a name outside the sonora namespace", async () => {
    const store = createLocalSecretStore(directory);

    await expect(store.get("other/staging/db/identity")).rejects.toThrow();
  });
});
