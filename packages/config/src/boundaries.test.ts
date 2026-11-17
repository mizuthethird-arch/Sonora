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

  it("pass when a module imports the public entry of another module", () => {
    const result = runBoundaryCheck("module-imports-public");

    expect(result.status).toBe(0);
  });

  it("fail when an app reaches past the public entry of a module", () => {
    const result = runBoundaryCheck("app-past-public-entry");

    expect(result.status).not.toBe(0);
    expect(result.output).toContain("no-app-past-public-entry");
  });

  it("pass when an app uses module.ts and public entries", () => {
    const result = runBoundaryCheck("app-uses-public-entries");

    expect(result.status).toBe(0);
  });

  it("fail when a package imports a module", () => {
    const result = runBoundaryCheck("package-imports-module");

    expect(result.status).not.toBe(0);
    expect(result.output).toContain("no-package-imports-module-or-app");
  });

  it("fail when a database client is imported outside the infrastructure folder", () => {
    const result = runBoundaryCheck("database-client-outside-infrastructure");

    expect(result.status).not.toBe(0);
    expect(result.output).toContain("no-database-client-outside-infrastructure");
  });

  it("pass when a database client is imported inside the infrastructure folder", () => {
    const result = runBoundaryCheck("database-client-in-infrastructure");

    expect(result.status).toBe(0);
  });
});
