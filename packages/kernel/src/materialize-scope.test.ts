import { mkdtempSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { materializeSecrets } from "./materialize.js";
import { type SecretStore } from "./secrets.js";

let root: string;

beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), "sonora-scope-"));
});

afterEach(() => {
  rmSync(root, { recursive: true, force: true });
});

const store: SecretStore = {
  get: (name) => Promise.resolve(`value-of-${name}`),
};

describe("materializeSecrets scope", () => {
  it("refuses a staging run that asks for a production secret, and writes nothing", async () => {
    const target = join(root, "run");

    await expect(
      materializeSecrets({
        store,
        environment: "staging",
        names: ["sonora/staging/db/identity", "sonora/production/db/identity"],
        directory: target,
      }),
    ).rejects.toThrow(/production/);
    expect(existsSync(join(target, "identity"))).toBe(false);
  });

  it("accepts secrets of the environment it was asked for", async () => {
    const target = join(root, "run");

    const written = await materializeSecrets({
      store,
      environment: "staging",
      names: ["sonora/staging/db/identity"],
      directory: target,
    });

    expect(written).toHaveLength(1);
  });
});
