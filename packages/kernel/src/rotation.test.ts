import { mkdtempSync, readFileSync, rmSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { materializeSecrets } from "./materialize.js";
import { createLocalSecretStore } from "./secrets.js";

let root: string;

beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), "sonora-rotation-"));
});

afterEach(() => {
  rmSync(root, { recursive: true, force: true });
});

describe("secret rotation", () => {
  it("writes the new value on the next materialize after the store changes", async () => {
    const storeDirectory = join(root, "store");
    mkdirSync(join(storeDirectory, "sonora/staging/db"), { recursive: true });
    const secretPath = join(storeDirectory, "sonora/staging/db/identity");
    const target = join(root, "run");
    const store = createLocalSecretStore(storeDirectory);

    writeFileSync(secretPath, "value-before-rotation\n");
    await materializeSecrets({ store, environment: "staging", names: ["sonora/staging/db/identity"], directory: target });
    expect(readFileSync(join(target, "identity"), "utf8")).toBe("value-before-rotation");

    writeFileSync(secretPath, "value-after-rotation\n");
    await materializeSecrets({ store, environment: "staging", names: ["sonora/staging/db/identity"], directory: target });

    expect(readFileSync(join(target, "identity"), "utf8")).toBe("value-after-rotation");
  });
});
