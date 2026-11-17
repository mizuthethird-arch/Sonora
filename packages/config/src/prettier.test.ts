import { format } from "prettier";
import { describe, expect, it } from "vitest";
import prettierConfig from "../prettier.config.js";

describe("the shared Prettier config", () => {
  it("uses double quotes, semicolons and trailing commas", async () => {
    const formatted = await format("const names = ['a',\n'b']\n", { ...prettierConfig, parser: "typescript", printWidth: 10 });

    expect(formatted).toBe('const names = [\n  "a",\n  "b",\n];\n');
  });

  it("allows lines up to 120 characters", () => {
    expect(prettierConfig.printWidth).toBe(120);
  });
});
