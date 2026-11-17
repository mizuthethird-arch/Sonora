import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const baseConfig = JSON.parse(
  readFileSync(fileURLToPath(new URL("../tsconfig.base.json", import.meta.url)), "utf8"),
) as {
  compilerOptions: Record<string, unknown>;
};

describe("tsconfig.base.json", () => {
  it("is strict, checks indexed access and targets ES2022", () => {
    expect(baseConfig.compilerOptions).toMatchObject({
      strict: true,
      noUncheckedIndexedAccess: true,
      target: "ES2022",
    });
  });
});
