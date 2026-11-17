import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { runBoundaryCheckIn } from "./boundary-check.js";

const fixtureRoot = fileURLToPath(new URL("../fixtures/", import.meta.url));

function runBoundaryCheck(fixtureName: string): { status: number | null; output: string } {
  return runBoundaryCheckIn(`${fixtureRoot}${fixtureName}`);
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

  it("fail when two module facades depend on each other", () => {
    const result = runBoundaryCheck("circular-module-facades");

    expect(result.status).not.toBe(0);
    expect(result.output).toContain("no-circular-module-facades");
  });

  it("pass when modules, apps and packages import types from packages/contracts", () => {
    const result = runBoundaryCheck("type-only-contracts-everywhere");

    expect(result.status).toBe(0);
  });

  it("fail when a cycle between two modules runs through their internals", () => {
    const result = runBoundaryCheck("circular-through-internals");

    expect(result.status).not.toBe(0);
    expect(result.output).toContain("no-circular-module-facades");
  });

  it("fail when the generated Prisma client is imported outside the database folder", () => {
    const result = runBoundaryCheck("generated-client-outside-database");

    expect(result.status).not.toBe(0);
    expect(result.output).toContain("no-database-client-outside-infrastructure");
  });

  it("fail when a folder named fixtures hides a module internals import", () => {
    const result = runBoundaryCheck("fixtures-folder-does-not-hide-imports");

    expect(result.status).not.toBe(0);
    expect(result.output).toContain("no-module-internals");
  });

  it("fail when a module imports an app", () => {
    const result = runBoundaryCheck("module-imports-app");

    expect(result.status).not.toBe(0);
    expect(result.output).toContain("no-module-imports-app");
  });
});
