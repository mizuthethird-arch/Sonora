import { ESLint } from "eslint";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const fixtureDirectory = fileURLToPath(new URL("../fixtures/lint/", import.meta.url));
const configFile = fileURLToPath(new URL("../eslint.config.js", import.meta.url));

async function lintedRuleIds(fileName: string): Promise<(string | null)[]> {
  const eslint = new ESLint({ cwd: fixtureDirectory, overrideConfigFile: configFile });
  const [result] = await eslint.lintFiles([fileName]);
  return result?.messages.map((message) => message.ruleId) ?? [];
}

describe("the shared ESLint config", () => {
  it("reports a floating promise", async () => {
    expect(await lintedRuleIds("floating-promise.ts")).toContain("@typescript-eslint/no-floating-promises");
  });

  it("reports an explicit any", async () => {
    expect(await lintedRuleIds("explicit-any.ts")).toContain("@typescript-eslint/no-explicit-any");
  });

  it("accepts an awaited promise", async () => {
    expect(await lintedRuleIds("awaited-promise.ts")).toEqual([]);
  });
});
