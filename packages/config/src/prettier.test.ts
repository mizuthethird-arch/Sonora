import { format } from "prettier";
import { describe, expect, it } from "vitest";
import prettierConfig from "../prettier.config.js";

describe("the shared Prettier config", () => {
  it("uses double quotes, semicolons and trailing commas", async () => {
    const formatted = await format("const options = {\n  a: 'x',\n  b: 'y'\n}\n", {
      ...prettierConfig,
      parser: "typescript",
    });

    expect(formatted).toBe('const options = {\n  a: "x",\n  b: "y",\n};\n');
  });

  it("allows lines up to 120 characters", () => {
    expect(prettierConfig.printWidth).toBe(120);
  });
});
