import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

type Rule = { name: string; comment: string };

const require = createRequire(import.meta.url);
const rules = (require("../boundaries.cjs") as { forbidden: Rule[] }).forbidden;
const documentation = readFileSync(fileURLToPath(new URL("../../../docs/boundaries.md", import.meta.url)), "utf8");
const sections = documentation.split(/^## /m).slice(1);

function sectionOf(ruleName: string): string {
  return sections.find((section) => section.startsWith(`${ruleName}\n`)) ?? "";
}

describe.each(rules)("rule $name", (rule) => {
  it("has a section in docs/boundaries.md", () => {
    expect(sectionOf(rule.name)).not.toBe("");
  });

  it("shows a bad and a good example", () => {
    const section = sectionOf(rule.name);

    expect(section).toContain("**Bad**");
    expect(section).toContain("**Good**");
    expect(section.match(/```/g)).toHaveLength(4);
  });

  it("is linked from its failure message", () => {
    expect(rule.comment).toContain(`docs/boundaries.md#${rule.name}`);
  });
});
