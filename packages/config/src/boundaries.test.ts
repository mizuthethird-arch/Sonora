import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const boundaryConfig = fileURLToPath(new URL("../boundaries.cjs", import.meta.url));
const fixtureRoot = fileURLToPath(new URL("../fixtures/", import.meta.url));

function runBoundaryCheck(fixtureName: string): { status: number | null; output: string } {
  const result = spawnSync(
    "pnpm",
    ["exec", "depcruise", ".", "--config", boundaryConfig, "--output-type", "err-long"],
    { cwd: `${fixtureRoot}${fixtureName}`, encoding: "utf8" },
  );
  return { status: result.status, output: `${result.stdout}${result.stderr}` };
}

describe("module boundaries", () => {
  it("fail when a module imports the internals of another module", () => {
    const result = runBoundaryCheck("module-imports-internals");

    expect(result.status).not.toBe(0);
    expect(result.output).toContain("no-module-internals");
  });
});
