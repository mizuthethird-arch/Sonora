import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import { runBoundaryCheckIn } from "./boundary-check.js";

const workDirectory = mkdtempSync(join(tmpdir(), "boundaries-"));

function writeFile(relativePath: string, content: string): void {
  const path = join(workDirectory, relativePath);
  mkdirSync(join(path, ".."), { recursive: true });
  writeFileSync(path, content);
}

afterAll(() => {
  rmSync(workDirectory, { recursive: true, force: true });
});

describe("a database client that resolves into node_modules", () => {
  it("is caught outside the infrastructure folder", () => {
    writeFile("node_modules/mysql2/package.json", '{ "name": "mysql2", "version": "0.0.0", "main": "index.js" }');
    writeFile("node_modules/mysql2/index.js", "module.exports = {};");
    writeFile("apps/api/src/routes.ts", 'import mysql from "mysql2";\n\nexport const client = mysql;\n');

    const result = runBoundaryCheckIn(workDirectory);

    expect(result.status).not.toBe(0);
    expect(result.output).toContain("no-database-client-outside-infrastructure");
  });
});
