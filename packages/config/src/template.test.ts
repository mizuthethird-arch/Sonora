import { ESLint } from "eslint";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const templateDirectory = fileURLToPath(new URL("../../../modules/_template/", import.meta.url));

function readTemplateFile(name: string): string {
  return readFileSync(`${templateDirectory}${name}`, "utf8");
}

describe("modules/_template", () => {
  const packageJson = JSON.parse(readTemplateFile("package.json")) as {
    devDependencies: Record<string, string>;
    scripts: Record<string, string>;
    prettier: string;
  };

  it("depends on @sonora/config and takes its Prettier config", () => {
    expect(packageJson.devDependencies["@sonora/config"]).toBe("workspace:*");
    expect(packageJson.prettier).toBe("@sonora/config/prettier");
  });

  it("only re-exports the ESLint config, with no local overrides", () => {
    expect(readTemplateFile("eslint.config.js")).toBe('export { default } from "@sonora/config/eslint";\n');
  });

  it("only extends the base tsconfig, with no local compiler options", () => {
    const tsconfig = JSON.parse(readTemplateFile("tsconfig.json")) as Record<string, unknown>;

    expect(tsconfig).toEqual({ extends: "@sonora/config/tsconfig.base.json", include: ["src"] });
  });

  it("has lint and typecheck scripts", () => {
    expect(packageJson.scripts).toMatchObject({ lint: "eslint .", typecheck: "tsc --noEmit" });
  });

  it("passes ESLint", async () => {
    const results = await new ESLint({ cwd: templateDirectory }).lintFiles(["."]);

    expect(results.flatMap((result) => result.messages)).toEqual([]);
  });

  it("passes the typecheck", () => {
    const result = spawnSync("pnpm", ["exec", "tsc", "--noEmit"], { cwd: templateDirectory, encoding: "utf8" });

    expect(result.error).toBeUndefined();
    expect(result.stdout + result.stderr).toBe("");
    expect(result.status).toBe(0);
  });
});
