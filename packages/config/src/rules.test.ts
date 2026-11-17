import { createRequire } from "node:module";
import { describe, expect, it } from "vitest";

type Rule = { name: string; severity: string; to: { path?: string } };
type Config = { forbidden: Rule[]; options: { exclude: { path: string } } };

const require = createRequire(import.meta.url);
const config = require("../boundaries.cjs") as Config;

const EXPECTED_EXCLUDE = "^packages/config/fixtures/|(^|/)node_modules/|^apps/[^/]+/dist/";

describe("boundary configuration", () => {
  it("makes every rule an error", () => {
    expect(config.forbidden.filter((rule) => rule.severity !== "error")).toEqual([]);
  });

  it("excludes only the fixtures of this package, node_modules and build output of apps", () => {
    expect(config.options.exclude.path).toBe(EXPECTED_EXCLUDE);
  });

  describe("database client rule", () => {
    const rule = config.forbidden.find((candidate) => candidate.name === "no-database-client-outside-infrastructure");
    const matches = (path: string) => new RegExp(rule?.to.path ?? "$^").test(path);

    it.each([
      "node_modules/.pnpm/@prisma+client@7.10.1/node_modules/@prisma/client/index.js",
      "mysql2",
      "pg",
      "kysely",
      "apps/api/src/generated/prisma/client.ts",
    ])("matches %s", (path) => {
      expect(matches(path)).toBe(true);
    });

    it.each(["node_modules/zod/index.js", "express", "modules/catalog/src/public/index.ts"])("ignores %s", (path) => {
      expect(matches(path)).toBe(false);
    });
  });
});
