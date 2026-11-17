import { existsSync, readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { findForbiddenExports } from "./public-entry.js";

const modulesDirectory = fileURLToPath(new URL("../../../modules/", import.meta.url));
const moduleNames = readdirSync(modulesDirectory, { withFileTypes: true })
  .filter((entry) => entry.isDirectory())
  .map((entry) => entry.name);

describe("module folders", () => {
  it("include the template and the first two modules", () => {
    expect(moduleNames).toEqual(expect.arrayContaining(["_template", "catalog", "playback"]));
  });
});

describe.each(moduleNames)("module %s", (moduleName) => {
  const publicEntry = `${modulesDirectory}${moduleName}/src/public/index.ts`;

  it("has a public entry", () => {
    expect(existsSync(publicEntry)).toBe(true);
  });

  it("exports only its facade, its types and its event schemas", () => {
    expect(findForbiddenExports(readFileSync(publicEntry, "utf8"))).toEqual([]);
  });
});
